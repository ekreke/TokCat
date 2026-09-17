import AppKit
import SwiftUI
import TokCatCore
import TokCatSources
import TokCatAgent
import TokCatEngine

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
    private lazy var hermesSettings = HermesSettingsController(settings: settings) { [weak self] in
        self?.chat.shutdown()
    }

    private var trendChartHosting: NSHostingView<TrendChartView>?
    private lazy var trendChartItem = makeTrendChartItem()
    private var localHermesPath: String?

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

        chat.setSetupHandler { [weak self] in self?.hermesSettings.show() }

        // 预热：提前建好 Chat 弹窗与趋势图 hosting view，并后台解析 Agent 状态，
        // 避免第一次点击时才在主线程做这些耗时工作。
        _ = chat
        _ = trendChartItem
        DispatchQueue.global(qos: .utility).async { _ = ShellEnvironment.loginPath() }
        refreshHermesStatusInBackground()

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
        chat.shutdown()
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

        // 后台刷新 Agent 检测缓存（安装后菜单能反映最新状态），菜单本身读缓存不阻塞。
        refreshHermesStatusInBackground()

        refreshTrendChart()
        menu.addItem(trendChartItem)

        menu.addItem(.separator())
        menu.addItem(settingsMenu())
        menu.addItem(.separator())
        menu.addItem(item("退出 TokCat", #selector(quit), key: "q"))
    }

    /// 「设置 ▸」：全部可调项收进二级子菜单，右键顶栏只留 趋势图 / 设置 / 退出。
    private func settingsMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(hermesMenu())
        submenu.addItem(animationMenu())
        submenu.addItem(metricMenu())
        submenu.addItem(sizeMenu())
        submenu.addItem(maxFPSMenu())
        submenu.addItem(sensitivityMenu())
        submenu.addItem(sourcesMenu())

        submenu.addItem(.separator())
        submenu.addItem(item("重载模型定价", #selector(reloadPricing)))
        submenu.addItem(item("重置统计", #selector(resetTotals)))

        submenu.addItem(.separator())
        submenu.addItem(loginItemMenu())

        parent.submenu = submenu
        return parent
    }

    /// 菜单顶部的趋势图（复用同一个 hosting view，避免每次重开都新建、首次也更快）。
    private func makeTrendChartItem() -> NSMenuItem {
        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: TrendChartView(data: .empty))
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 200)
        trendChartHosting = hosting
        item.view = hosting
        return item
    }

    /// 取一份当前快照刷新图表（菜单打开时调用一次，打开期间不再重绘）。
    private func refreshTrendChart() {
        guard let hosting = trendChartHosting else { return }
        hosting.rootView = TrendChartView(data: trendModel.chartData())
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let height = fitting.height > 60 ? fitting.height : 200
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: height)
    }

    private func hermesMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Hermes", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for mode in HermesMode.allCases {
            let entry = NSMenuItem(title: mode.displayName, action: #selector(selectHermesMode(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = mode == settings.hermesMode ? .on : .off
            submenu.addItem(entry)
        }
        let detail = NSMenuItem(title: hermesDetail(), action: nil, keyEquivalent: "")
        detail.isEnabled = false
        submenu.addItem(detail)

        submenu.addItem(.separator())
        submenu.addItem(item("Hermes 设置…", #selector(openHermesSettings)))
        submenu.addItem(item("断开 Agent", #selector(disconnectAgent)))
        parent.submenu = submenu
        return parent
    }

    private func hermesDetail() -> String {
        switch settings.hermesMode {
        case .local:
            return localHermesPath != nil ? "已检测到本地 hermes" : "本地未安装"
        case .remote:
            let target = settings.sshTarget.trimmingCharacters(in: .whitespaces)
            return target.isEmpty ? "未配置 SSH 目标" : "SSH: \(target)"
        }
    }

    /// 后台刷新本地 hermes 检测结果，菜单读取缓存避免触发 shell。
    private func refreshHermesStatusInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let path: String?
            switch AgentDetector.localStatus() {
            case let .ready(value): path = value
            case .missing: path = nil
            }
            DispatchQueue.main.async { self.localHermesPath = path }
        }
    }

    @objc private func disconnectAgent() {
        chat.shutdown()
    }

    @objc private func selectHermesMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = HermesMode(rawValue: raw) else { return }
        settings.hermesMode = mode
        chat.shutdown()
    }

    @objc private func openHermesSettings() {
        hermesSettings.show()
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

    private func loginItemMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "开机自启", action: #selector(toggleLoginItem), keyEquivalent: "")
        item.target = self
        switch LoginItemManager.currentState() {
        case .enabled:
            item.state = .on
        case .requiresApproval:
            item.title = "开机自启（需在系统设置中允许…）"
            item.state = .off
        case .disabled, .failed:
            item.state = .off
        case .unsupported:
            item.state = .off
            item.isEnabled = false
        }
        return item
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
        trendModel.setMetricName(kind.displayName)
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
        let target = !LoginItemManager.isEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = LoginItemManager.setEnabled(target)
            DispatchQueue.main.async { self?.handleLoginItemResult(state) }
        }
    }

    private func handleLoginItemResult(_ state: LoginItemState) {
        switch state {
        case .enabled(let mechanism):
            if mechanism == .launchAgent {
                NSLog("TokCat: 已通过 LaunchAgent 开启开机自启")
            }
        case .requiresApproval:
            presentLoginItemAlert(
                title: "需要你的允许",
                message: "TokCat 已加入登录项，但需要在「系统设置 → 通用 → 登录项」中允许后才会生效。",
                openSettings: true
            )
        case .failed(let message):
            presentLoginItemAlert(title: "设置开机自启失败", message: message, openSettings: false)
        case .disabled, .unsupported:
            break
        }
    }

    private func presentLoginItemAlert(title: String, message: String, openSettings: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        if openSettings {
            alert.addButton(withTitle: "打开登录项设置")
            alert.addButton(withTitle: "稍后")
        } else {
            alert.addButton(withTitle: "好")
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if openSettings, response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
