import AppKit
import SwiftUI

struct WindowTitlebarAccessory<Content: View>: NSViewRepresentable {
    let placement: NSLayoutConstraint.Attribute
    let content: Content

    init(placement: NSLayoutConstraint.Attribute = .trailing, content: Content) {
        self.placement = placement
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(placement: placement, rootView: AnyView(content))
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(rootView: AnyView(content))
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private let controller = NSTitlebarAccessoryViewController()
        private let hostingView: NSHostingView<AnyView>
        private weak var window: NSWindow?

        init(placement: NSLayoutConstraint.Attribute, rootView: AnyView) {
            controller.layoutAttribute = placement
            hostingView = NSHostingView(rootView: rootView)
            controller.view = hostingView
            update(rootView: rootView)
        }

        func update(rootView: AnyView) {
            hostingView.rootView = rootView
            hostingView.layoutSubtreeIfNeeded()
            hostingView.setFrameSize(hostingView.fittingSize)
            controller.view.invalidateIntrinsicContentSize()
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard self.window !== window else { return }

            detach()
            self.window = window
            window.addTitlebarAccessoryViewController(controller)
        }

        func detach() {
            guard let window else { return }
            if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === controller }) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.window = nil
        }
    }
}
