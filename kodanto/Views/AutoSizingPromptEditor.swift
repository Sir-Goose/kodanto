import AppKit
import SwiftUI

struct AutoSizingPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let font: NSFont
    let textInset: NSSize
    let maxHeight: CGFloat
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
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.documentView = textView

        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        textView.coordinator = context.coordinator
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        context.coordinator.scheduleHeightRecalculation()

        return scrollView
    }

    func updateNSView(_ nsView: PromptScrollView, context: Context) {
        let previousParent = context.coordinator.parent
        context.coordinator.parent = self

        guard let textView = context.coordinator.textView else { return }

        var needsHeightUpdate = false

        if textView.string != text {
            textView.string = text
            needsHeightUpdate = true
        }

        if textView.font != font {
            textView.font = font
            needsHeightUpdate = true
        }

        if textView.textContainerInset != textInset {
            textView.textContainerInset = textInset
            needsHeightUpdate = true
        }

        if abs(previousParent.maxHeight - maxHeight) > 0.5 {
            needsHeightUpdate = true
        }

        textView.onSubmit = onSubmit

        if needsHeightUpdate {
            context.coordinator.scheduleHeightRecalculation()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoSizingPromptEditor
        weak var scrollView: PromptScrollView?
        weak var textView: PromptTextView?

        private var isHeightRecalculationScheduled = false
        private var isRecalculatingHeight = false
        private var needsAnotherHeightPass = false

        init(parent: AutoSizingPromptEditor) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let updatedText = textView.string

            if parent.text != updatedText {
                parent.text = updatedText
            }

            scheduleHeightRecalculation()
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView else { return }
            let updatedText = textView.string
            if parent.text != updatedText {
                parent.text = updatedText
            }
        }

        @objc
        func clipViewFrameDidChange(_ notification: Notification) {
            scheduleHeightRecalculation()
        }

        func scheduleHeightRecalculation() {
            if isRecalculatingHeight {
                needsAnotherHeightPass = true
                return
            }

            guard !isHeightRecalculationScheduled else { return }

            isHeightRecalculationScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.performHeightRecalculation()
            }
        }

        private func performHeightRecalculation() {
            isHeightRecalculationScheduled = false
            recalculateHeight()
        }

        private func recalculateHeight() {
            guard !isRecalculatingHeight else {
                needsAnotherHeightPass = true
                return
            }

            isRecalculatingHeight = true
            defer {
                isRecalculatingHeight = false

                if needsAnotherHeightPass {
                    needsAnotherHeightPass = false
                    scheduleHeightRecalculation()
                }
            }

            guard let textView, let scrollView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }

            let availableWidth = max(scrollView.contentSize.width, 1)
            if textContainer.containerSize.width != availableWidth {
                textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            }

            layoutManager.ensureLayout(for: textContainer)

            let usedRect = layoutManager.usedRect(for: textContainer)
            let minimumLineHeight = ceil(layoutManager.defaultLineHeight(for: textView.font ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)) + (textView.textContainerInset.height * 2))
            let contentHeight = max(minimumLineHeight, ceil(usedRect.height + (textView.textContainerInset.height * 2)))
            let targetVisibleHeight = min(contentHeight, max(parent.maxHeight, minimumLineHeight))
            let documentHeight = max(contentHeight, targetVisibleHeight)

            if textView.frame.size.width != availableWidth || textView.frame.size.height != documentHeight {
                textView.setFrameSize(NSSize(width: availableWidth, height: documentHeight))
            }

            if abs(parent.measuredHeight - targetVisibleHeight) > 0.5 {
                parent.measuredHeight = targetVisibleHeight
            }

            let shouldScroll = contentHeight > targetVisibleHeight + 0.5
            if scrollView.hasVerticalScroller != shouldScroll {
                scrollView.hasVerticalScroller = shouldScroll
            }
        }
    }
}

final class PromptScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
}

final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    weak var coordinator: AutoSizingPromptEditor.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        coordinator?.scheduleHeightRecalculation()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
