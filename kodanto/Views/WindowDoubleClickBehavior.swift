import AppKit
import SwiftUI

enum WindowDoubleClickAction: Equatable {
    case zoom
    case minimize
    case none
}

enum WindowDoubleClickPreferenceResolver {
    private static let actionOnDoubleClickKey = "AppleActionOnDoubleClick"
    private static let miniaturizeOnDoubleClickKey = "AppleMiniaturizeOnDoubleClick"

    static func resolve(defaults: UserDefaults = .standard) -> WindowDoubleClickAction {
        let value = defaults.string(forKey: actionOnDoubleClickKey)
        let legacyMiniaturize = defaults.object(forKey: miniaturizeOnDoubleClickKey) as? Bool
        return resolve(actionOnDoubleClickValue: value, legacyMiniaturize: legacyMiniaturize)
    }

    static func resolve(
        actionOnDoubleClickValue: String?,
        legacyMiniaturize: Bool?
    ) -> WindowDoubleClickAction {
        if let actionOnDoubleClickValue {
            let normalizedValue = actionOnDoubleClickValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedValue.caseInsensitiveCompare("Minimize") == .orderedSame {
                return .minimize
            }
            if normalizedValue.caseInsensitiveCompare("None") == .orderedSame {
                return .none
            }
            return .zoom
        }

        if let legacyMiniaturize {
            return legacyMiniaturize ? .minimize : .zoom
        }

        return .zoom
    }
}

struct WindowDoubleClickBehavior: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    static func isTopChromeHit(locationInWindowY: CGFloat, contentLayoutMaxY: CGFloat) -> Bool {
        locationInWindowY >= contentLayoutMaxY
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var eventMonitor: Any?

        deinit {
            detach()
        }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard self.window !== window else { return }

            detach()
            self.window = window
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event: event) ? nil : event
            }
        }

        func detach() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            window = nil
        }

        private func handle(event: NSEvent) -> Bool {
            guard event.clickCount == 2 else { return false }
            guard let window, event.window === window else { return false }
            guard WindowDoubleClickBehavior.isTopChromeHit(
                locationInWindowY: event.locationInWindow.y,
                contentLayoutMaxY: window.contentLayoutRect.maxY
            ) else {
                return false
            }

            if let hitView = hitView(at: event.locationInWindow, in: window),
               Self.isInteractiveHitView(hitView) {
                return false
            }

            switch WindowDoubleClickPreferenceResolver.resolve() {
            case .zoom:
                window.performZoom(nil)
                return true
            case .minimize:
                window.performMiniaturize(nil)
                return true
            case .none:
                return true
            }
        }

        private func hitView(at locationInWindow: NSPoint, in window: NSWindow) -> NSView? {
            guard let frameView = window.contentView?.superview else { return nil }
            let pointInFrameView = frameView.convert(locationInWindow, from: nil)
            return frameView.hitTest(pointInFrameView)
        }

        private static func isInteractiveHitView(_ view: NSView) -> Bool {
            var currentView: NSView? = view

            while let candidate = currentView {
                if candidate is NSControl || candidate is NSTextView {
                    return true
                }

                if let role = candidate.accessibilityRole(),
                   role == .button || role == .textField || role == .radioButton || role == .checkBox {
                    return true
                }

                currentView = candidate.superview
            }

            return false
        }
    }
}
