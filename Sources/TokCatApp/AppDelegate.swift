import AppKit
import TokCatCore
import TokCatSources
import TokCatEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?
    private let store = SourceStateStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install()
        AnimationRegistry.shared.loadAll()
        let bundled = BundledAnimations.register()
        if Debug.enabled {
            Debug.log("动画包: \(AnimationRegistry.shared.allPacks.map(\.displayName).joined(separator: ", ")) (内置素材包 \(bundled) 个)")
        }

        let pricing = ModelPricingStore.loadDefault()
        var sources = SourceFactory.makeDefault(store: store)
        sources.append(FakeTokenSource())

        let controller = StatusItemController(pricing: pricing, sources: sources, stateStore: store)
        controller.start()
        self.controller = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
        store.pruneMissingFiles()
        store.save()
    }
}
