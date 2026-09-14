import AppKit
import TokCatCore
import TokCatSources

/// 状态栏控制器：负责动画渲染与下拉菜单交互。
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let registry = AnimationRegistry.shared
    private let settings: AppSettings
    private let engine: RateEngine
    private var pricing: ModelPricingTable
    private let sources: [TokenSource]

    private var frameTimer: Timer?
    private var lastFrameTick: Date?
    private var frameIndex = 0
    private var accumulator: TimeInterval = 0

    private var currentRate: Double = 0
    private var snapshot: RateSnapshot?

    private let frameRate: Double = 30
    private var renderHeight: CGFloat { max(14, NSStatusBar.system.thickness - 4) }

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
            self?.currentRate = snapshot.rate
            self?.snapshot = snapshot
        }
    }

    func start() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imageScaling = .scaleProportionallyDown

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

    private var currentPack: AnimationPack {
        registry.pack(identifier: settings.animationIdentifier) ?? registry.defaultPack ?? BuiltinCatPack()
    }

    private var mapper: AnimationSpeedMapper {
        AnimationSpeedMapper(sensitivity: settings.sensitivity, saturationRate: settings.saturationRate)
    }

    private func startFrameTimer() {
        let timer = Timer(timeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    private func advanceFrame() {
        let now = Date()
        let dt = lastFrameTick.map { now.timeIntervalSince($0) } ?? (1.0 / frameRate)
        lastFrameTick = now

        let pack = currentPack
        let interval = mapper.frameInterval(rate: currentRate, pack: pack)
        accumulator += dt
        guard accumulator >= interval else { return }
        accumulator.formTruncatingRemainder(dividingBy: interval)

        frameIndex = (frameIndex + 1) % max(pack.frameCount, 1)
        renderFrame(pack: pack)
        if Debug.enabled { Debug.log("frame=\(frameIndex) rate=\(String(format: "%.1f", currentRate)) interval=\(String(format: "%.2f", interval))s") }
    }

    private func renderFrame(pack: AnimationPack? = nil) {
        let pack = pack ?? currentPack
        statusItem.button?.image = pack.image(frameIndex: frameIndex, height: renderHeight)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let rateText = Formatting.rate(currentRate, currency: snapshot?.unitIsCurrency ?? false)
        let header = NSMenuItem(title: "TokCat · \(rateText)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let totals = snapshot
        let totalText = Formatting.units(totals?.totalUnits ?? 0, currency: totals?.unitIsCurrency ?? false)
        let totalItem = NSMenuItem(title: "本次累计: \(totalText)", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        menu.addItem(totalItem)

        let usage = totals?.totalUsage ?? .zero
        let breakdown = NSMenuItem(
            title: "in \(Formatting.compact(usage.input)) · out \(Formatting.compact(usage.output)) · cache \(Formatting.compact(usage.cacheRead))",
            action: nil, keyEquivalent: ""
        )
        breakdown.isEnabled = false
        menu.addItem(breakdown)

        menu.addItem(.separator())

        menu.addItem(animationMenu())
        menu.addItem(metricMenu())
        menu.addItem(sensitivityMenu())
        menu.addItem(sourcesMenu())

        menu.addItem(.separator())

        menu.addItem(item("重新扫描动画目录", #selector(reloadAnimations)))
        menu.addItem(item("重载模型定价", #selector(reloadPricing)))
        let openItem = item("打开动画目录", #selector(openAnimationsFolder))
        menu.addItem(openItem)
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

    private func animationMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "动画", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for pack in registry.allPacks {
            let item = NSMenuItem(title: pack.displayName, action: #selector(selectAnimation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pack.identifier
            item.state = pack.identifier == currentPack.identifier ? .on : .off
            submenu.addItem(item)
        }
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
        frameIndex = 0
        accumulator = 0
        renderFrame()
    }

    @objc private func selectMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = MetricKind(rawValue: raw) else { return }
        settings.metricKind = kind
        engine.updateConverter(settings.makeConverter(pricing: pricing))
    }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        settings.sensitivity = value
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
