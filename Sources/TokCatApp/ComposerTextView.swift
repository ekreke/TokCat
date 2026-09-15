import AppKit
import SwiftUI

/// 支持多行、Enter 发送、粘贴/拖拽图片与文件的输入框（包装 `NSTextView`）。
///
/// - `Enter` 发送，`Shift+Enter` 换行。
/// - `⌘V`：剪贴板有图片 → 作为图片附件；有文件 → 作为文件附件；否则文本粘贴。
/// - 拖拽图片/文件到输入框同样作为附件。
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var isEnabled: Bool
    var onSubmit: () -> Void
    var onPasteImage: (Data) -> Void
    var onPasteFiles: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 34))
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.registerForDraggedTypes([.fileURL, .tiff, .png])

        // 关键：让文档视图随滚动视图宽度自适应，否则宽度为 0、文字不可见。
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.string = text
        textView.applyCallbacks(
            onSubmit: onSubmit,
            onPasteImage: onPasteImage,
            onPasteFiles: onPasteFiles
        )

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.applyCallbacks(
            onSubmit: onSubmit,
            onPasteImage: onPasteImage,
            onPasteFiles: onPasteFiles
        )
        textView.isEditable = isEnabled
        // 仅在外部改动（如补全命令/清空）时回写，避免打断正在进行的输入。
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if focused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 220
        guard let textView = context.coordinator.textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else {
            return CGSize(width: width, height: 36)
        }
        container.containerSize = NSSize(
            width: max(1, width - textView.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2
        return CGSize(width: width, height: min(max(used, 34), 96))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: PasteAwareTextView?

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }
    }
}

/// 拦截粘贴与回车、接收拖拽的 `NSTextView`。
final class PasteAwareTextView: NSTextView {
    private var onSubmit: (() -> Void)?
    private var onPasteImage: ((Data) -> Void)?
    private var onPasteFiles: (([URL]) -> Void)?

    func applyCallbacks(
        onSubmit: @escaping () -> Void,
        onPasteImage: @escaping (Data) -> Void,
        onPasteFiles: @escaping ([URL]) -> Void
    ) {
        self.onSubmit = onSubmit
        self.onPasteImage = onPasteImage
        self.onPasteFiles = onPasteFiles
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty {
            onPasteFiles?(urls)
            return
        }
        if let data = Self.imageData(from: pasteboard) {
            onPasteImage?(data)
            return
        }
        super.paste(sender)
    }

    /// 直接拦截 ⌘V：不依赖 Edit 菜单的启用状态（纯图片粘贴板会让菜单 Paste 变灰）。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            let pasteboard = NSPasteboard.general
            if let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty {
                onPasteFiles?(urls)
                return true
            }
            if let data = Self.imageData(from: pasteboard) {
                onPasteImage?(data)
                return true
            }
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if NSEvent.modifierFlags.contains(.shift) {
            super.insertNewline(sender)
        } else {
            onSubmit?()
        }
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        super.insertNewline(sender)
    }

    // MARK: - 拖拽

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if Self.imageData(from: pasteboard) != nil || !(Self.fileURLs(from: pasteboard) ?? []).isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = Self.fileURLs(from: pasteboard), !urls.isEmpty {
            onPasteFiles?(urls)
            return true
        }
        if let data = Self.imageData(from: pasteboard) {
            onPasteImage?(data)
            return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: - 剪贴板解析

    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        if let data = pasteboard.data(forType: .tiff) { return data }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first {
            return first.pngData()
        }
        return nil
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }
}
