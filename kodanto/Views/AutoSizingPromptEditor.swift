import AppKit
import SwiftUI

struct AutoSizingPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let font: NSFont
    let textInset: NSSize
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PromptScrollView {
        let scrollView = PromptScrollView()
        let textView = PromptTextView()

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = font
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = textInset
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.onSubmit = onSubmit

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        textView.coordinator = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return scrollView
    }

    func updateNSView(_ nsView: PromptScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        textView.font = font
        textView.textContainerInset = textInset
        textView.onSubmit = onSubmit

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingPromptEditor
        weak var scrollView: PromptScrollView?
        weak var textView: PromptTextView?

        init(parent: AutoSizingPromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let updatedText = textView.string

            if parent.text != updatedText {
                parent.text = updatedText
            }

            recalculateHeight()
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView else { return }
            let updatedText = textView.string
            if parent.text != updatedText {
                parent.text = updatedText
            }
        }

        func recalculateHeight() {
            guard let textView, let scrollView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

            let availableWidth = max(scrollView.contentSize.width, 1)
            if textContainer.containerSize.width != availableWidth {
                textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            }

            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let minimumLineHeight = ceil(layoutManager.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)) + (textView.textContainerInset.height * 2))
            let contentHeight = max(minimumLineHeight, ceil(usedRect.height + (textView.textContainerInset.height * 2)))
            let visibleHeight = max(scrollView.contentSize.height, minimumLineHeight)
            let documentHeight = max(contentHeight, visibleHeight)

            if textView.frame.size.width != availableWidth || textView.frame.size.height != documentHeight {
                textView.setFrameSize(NSSize(width: availableWidth, height: documentHeight))
            }

            if parent.measuredHeight != contentHeight {
                parent.measuredHeight = contentHeight
            }

            let shouldScroll = contentHeight > visibleHeight + 0.5
            if scrollView.hasVerticalScroller != shouldScroll {
                scrollView.hasVerticalScroller = shouldScroll
            }
        }
    }
}

final class PromptScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        if let textView = documentView as? PromptTextView {
            textView.coordinator?.recalculateHeight()
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        if let textView = documentView as? PromptTextView {
            textView.coordinator?.recalculateHeight()
        }
    }
}

final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    weak var coordinator: AutoSizingPromptEditor.Coordinator?

    override var frame: NSRect {
        didSet {
            if oldValue.size.width != frame.size.width {
                textContainer?.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
                coordinator?.recalculateHeight()
            }
        }
    }

    override func didChangeText() {
        super.didChangeText()
        coordinator?.recalculateHeight()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.recalculateHeight()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
