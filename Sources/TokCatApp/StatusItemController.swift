import AppKit
import SwiftUI
import TokCatCore
import TokCatSources
import TokCatAgent

/// 状态栏控制器：负责动画渲染与下拉菜单交互。
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let registry = AnimationRegistry.shared
    private let settings: AppSettings
    private let engine: RateEngine
    private var pricing: ModelPricingTable
    private let sources: [TokenSource]

    private let menu = NSMenu()
    private let trendModel = TrendModel()
    private lazy var chat = ChatPopoverController(settings: settings)
    private lazy var agentSetup = AgentSetupController(settings: settings)

    private var frameTimer: Timer?
    private var frameIndex = 0
    private var frameBaseIndex = 0
    private var frameBaseTime = Date()
    private var lastInterval: TimeInterval = 0

    private var currentRate: Double = 0
    private var snapshot: RateSnapshot?

    private var cachedPack: AnimationPack?
    private var cachedPackIdentifier: String?

    private let frameRate: Double = 60
    private var renderHeight: CGFloat { CGFloat(settings.iconSize) }

    init(pricing: ModelPricingTable = .empty,
         sources: [TokenSource]? = nil,
         stateStore: SourceStateStore? = nil) {
        let resolvedSettings = AppSettings()
        let resolvedSources = sources ?? SourceFactory.makeDefault()
        resolvedSettings.apply(to: resolvedSources)

        self.settings = resolvedSettings
        self.pricing = pricing
        self.sources = resolvedSources
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.engine = RateEngine(
            sources: resolvedSources,
            converter: resolvedSettings.makeConverter(pricing: pricing),
            stateStore: stateStore
        )
        super.init()
        trendModel.rangeMinutes = settings.trendRangeMinutes
        trendModel.onRangeChange = { [weak self] minutes in
            self?.settings.trendRangeMinutes = minutes
        }
        engine.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.currentRate = snapshot.rate
            self.snapshot = snapshot
            self.trendModel.update(from: snapshot, metricName: self.settings.metricKind.displayName)
        }
    }

    func start() {
        menu.delegate = self
        if let button = statusItem.button {
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        chat.setSetupHandler { [weak self] in self?.agentSetup.show() }

        renderFrame()
        engine.start()
        startFrameTimer()
        if Debug.enabled {
            Debug.log("statusItem button=\(statusItem.button != nil) visible=\(statusItem.isVisible) frame=\(statusItem.button?.frame ?? .zero) image=\(statusItem.button?.image?.size ?? .zero)")
        }
    }

    func stop() {
        frameTimer?.invalidate()
        frameTimer = nil
        engine.stop()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Animation

    private func resolvePack() -> AnimationPack? {
        if let cachedPack, cachedPackIdentifier == settings.animationIdentifier {
            return cachedPack
        }
        let pack = registry.pack(identifier: settings.animationIdentifier) ?? registry.defaultPack
        cachedPack = pack
        cachedPackIdentifier = settings.animationIdentifier
        return pack
    }

    private func invalidatePackCache() {
        cachedPack = nil
        cachedPackIdentifier = nil
    }

    private func startFrameTimer() {
        let timer = Timer(timeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    /// 基于墙钟推进帧号：速率变化时重设基准，主线程偶发阻塞后直接跳到正确帧，
    /// 避免固定 tick 累加带来的量化抖动。
    private func advanceFrame() {
        guard let pack = resolvePack() else { return }

        let mapper = AnimationSpeedMapper(
            sensitivity: settings.sensitivity,
            saturationRate: settings.saturationRate,
            maxFPS: settings.maxFPS
        )
        let interval = mapper.frameInterval(rate: currentRate, pack: pack)
        let now = Date()

        if abs(interval - lastInterval) > 0.0005 {
            frameBaseIndex = frameIndex
            frameBaseTime = now
            lastInterval = interval
        }

        let elapsed = now.timeIntervalSince(frameBaseTime)
        let advance = Int((elapsed / interval).rounded(.down))
        let newIndex = ((frameBaseIndex + advance) % max(pack.frameCount, 1) + max(pack.frameCount, 1)) % max(pack.frameCount, 1)
        guard newIndex != frameIndex else { return }

        frameIndex = newIndex
        renderFrame(pack: pack)
        if Debug.enabled {
            Debug.log("frame=\(frameIndex) rate=\(String(format: "%.1f", currentRate)) interval=\(String(format: "%.0f", interval * 1000))ms")
        }
    }

    private func renderFrame(pack: AnimationPack? = nil) {
        guard let pack = pack ?? resolvePack() else {
            statusItem.button?.image = nil
            return
        }
        // 单色素材始终走模板图，避免深色菜单栏下不可见；彩色素材保留原色。
        statusItem.button?.image = pack.image(
            frameIndex: frameIndex,
            height: renderHeight,
            template: !pack.supportsColor
        )
    }

    // MARK: - Menu

    /// 左键弹 Chat，右键弹菜单。
    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            chat.close()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if let button = statusItem.button {
            chat.toggle(relativeTo: button)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(trendMenuItem())
        menu.addItem(trendRangeMenu())

        menu.addItem(.separator())

        menu.addItem(agentMenu())
        menu.addItem(animationMenu())
        menu.addItem(metricMenu())
        menu.addItem(sizeMenu())
        menu.addItem(maxFPSMenu())
        menu.addItem(sensitivityMenu())
        menu.addItem(sourcesMenu())

        menu.addItem(.separator())

        menu.addItem(item("重载模型定价", #selector(reloadPricing)))
        menu.addItem(item("重置统计", #selector(resetTotals)))

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItemManager.isEnabled ? .on : .off
        loginItem.isEnabled = LoginItemManager.isSupported
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(item("退出 TokCat", #selector(quit), key: "q"))
    }

    /// 菜单顶部的趋势图（目前左键的图挪到这里；不再显示文字统计）。
    private func trendMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: TrendChartView(model: trendModel))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 176)
        item.view = hosting
        return item
    }

    private func trendRangeMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "趋势范围", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in TrendModel.rangeOptions {
            let entry = NSMenuItem(title: "\(minutes) 分钟", action: #selector(selectTrendRange(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = minutes
            entry.state = minutes == trendModel.rangeMinutes ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func agentMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Agent", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for preset in AgentPreset.builtins {
            let status = AgentDetector.status(for: preset, customCommand: settings.customAgentCommand)
            let suffix: String
            switch status {
            case .ready: suffix = ""
            case .missing: suffix = preset.id == AgentPreset.customID ? "" : "（未安装）"
            }
            let entry = NSMenuItem(
                title: "\(preset.displayName)\(suffix)",
                action: #selector(selectAgent(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = preset.id
            entry.state = preset.id == settings.agentPresetId ? .on : .off
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("安装 / 重新检测…", #selector(openAgentSetup)))
        parent.submenu = submenu
        return parent
    }

    @objc private func selectTrendRange(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        trendModel.rangeMinutes = minutes
    }

    @objc private func selectAgent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if id == AgentPreset.customID {
            promptForCustomCommand()
            return
        }
        settings.agentPresetId = id
        chat.close()
    }

    private func promptForCustomCommand() {
        let alert = NSAlert()
        alert.messageText = "自定义 Agent 命令"
        alert.informativeText = "填写启动 ACP 的完整命令，例如 npx @zed-industries/claude-agent-acp"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = settings.customAgentCommand
        field.placeholderString = "命令 参数…"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let command = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        settings.customAgentCommand = command
        settings.agentPresetId = AgentPreset.customID
        chat.close()
    }

    @objc private func openAgentSetup() {
        agentSetup.show()
    }

    private func animationMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "动画", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for pack in registry.allPacks {
            let item = NSMenuItem(title: pack.displayName, action: #selector(selectAnimation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pack.identifier
            item.state = pack.identifier == resolvePack()?.identifier ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("重新扫描动画目录", #selector(reloadAnimations)))
        submenu.addItem(item("打开动画目录", #selector(openAnimationsFolder)))
        parent.submenu = submenu
        return parent
    }

    private func metricMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "速率口径", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for kind in MetricKind.allCases {
            let item = NSMenuItem(title: kind.displayName, action: #selector(selectMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = kind == settings.metricKind ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func sizeMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for size in [16.0, 18.0, 20.0, 22.0, 24.0] {
            let item = NSMenuItem(title: "\(Int(size)) pt", action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = abs(size - settings.iconSize) < 0.001 ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func maxFPSMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "最大帧率", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in [10.0, 20.0, 30.0, 40.0] {
            let item = NSMenuItem(title: "\(Int(value)) fps", action: #selector(selectMaxFPS(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(value - settings.maxFPS) < 0.001 ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func sensitivityMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "灵敏度", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in [0.25, 0.5, 1.0, 2.0, 4.0] {
            let item = NSMenuItem(title: "\(value)×", action: #selector(selectSensitivity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(value - settings.sensitivity) < 0.001 ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func sourcesMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "数据源", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for source in sources {
            let count = snapshot?.eventCounts[source.id] ?? 0
            let title = count > 0 ? "\(source.displayName)  (\(count))" : source.displayName
            let item = NSMenuItem(title: title, action: #selector(toggleSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = source.isEnabled ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func selectAnimation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.animationIdentifier = id
        invalidatePackCache()
        frameIndex = 0
        frameBaseIndex = 0
        frameBaseTime = Date()
        renderFrame()
    }

    @objc private func selectMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = MetricKind(rawValue: raw) else { return }
        settings.metricKind = kind
        engine.updateConverter(settings.makeConverter(pricing: pricing))
        trendModel.metricName = kind.displayName
    }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.sensitivity = value
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.iconSize = value
        renderFrame()
    }

    @objc private func selectMaxFPS(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.maxFPS = value
    }

    @objc private func toggleSource(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let source = sources.first(where: { $0.id == id }) else { return }
        let newValue = !source.isEnabled
        source.isEnabled = newValue
        settings.setEnabled(newValue, for: source)
    }

    @objc private func reloadAnimations() {
        let loaded = registry.loadAll()
        invalidatePackCache()
        renderFrame()
        NSLog("TokCat: 动画目录扫描完成，共 \(loaded) 个外部动画包")
    }

    @objc private func reloadPricing() {
        pricing = ModelPricingStore.loadDefault()
        engine.updateConverter(settings.makeConverter(pricing: pricing))
    }

    @objc private func openAnimationsFolder() {
        let url = AnimationRegistry.defaultExternalDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func resetTotals() {
        engine.resetTotals()
    }

    @objc private func toggleLoginItem() {
        LoginItemManager.setEnabled(!LoginItemManager.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
