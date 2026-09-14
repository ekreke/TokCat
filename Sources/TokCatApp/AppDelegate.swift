import AppKit
import TokCatCore
import TokCatSources

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?
    private let store = SourceStateStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AnimationRegistry.shared.loadAll()

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
