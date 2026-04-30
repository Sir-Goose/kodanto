import AppKit
import SwiftUI
import XCTest
@testable import kodanto

@MainActor
final class TranscriptBubbleLayoutTests: XCTestCase {
    func testUserPromptBubbleHugsContentAndAlignsTrailing() {
        let message = TestFixtures.userMessage(
            id: "user-1",
            createdAt: 1,
            parts: [
                TestFixtures.textPart(
                    id: "user-1-text",
                    messageID: "user-1",
                    text: "Short prompt"
                )
            ]
        )
        let turn = TranscriptTurn(user: message, assistantMessages: [])
        let image = render(
            TranscriptTurnView(
                turn: turn,
                worktreeRoot: nil,
                resolveTaskTarget: { _ in nil },
                navigateToSession: { _ in },
                disclosureStore: TranscriptDisclosureStore()
            )
            .accentColor(.red)
            .background(Color.white),
            size: CGSize(width: 520, height: 90)
        )

        let bubbleBounds = tintedBounds(in: image, renderedSize: CGSize(width: 520, height: 90))

        XCTAssertGreaterThan(bubbleBounds.minX, 360, "User bubble should be visually right aligned.")
        XCTAssertLessThan(abs(520 - bubbleBounds.maxX), 10, "User bubble should sit against the trailing edge.")
        XCTAssertLessThan(bubbleBounds.width, 180, "Short user bubble should hug its content, not fill the row.")
    }

    func testUserPromptBubbleWrapsBeforeFillingTranscriptWidth() {
        let message = TestFixtures.userMessage(
            id: "user-1",
            createdAt: 1,
            parts: [
                TestFixtures.textPart(
                    id: "user-1-text",
                    messageID: "user-1",
                    text: "This is a longer prompt that should wrap inside a chat bubble without taking the full transcript width."
                )
            ]
        )
        let turn = TranscriptTurn(user: message, assistantMessages: [])
        let image = render(
            TranscriptTurnView(
                turn: turn,
                worktreeRoot: nil,
                resolveTaskTarget: { _ in nil },
                navigateToSession: { _ in },
                disclosureStore: TranscriptDisclosureStore()
            )
            .accentColor(.red)
            .background(Color.white),
            size: CGSize(width: 520, height: 150)
        )

        let bubbleBounds = tintedBounds(in: image, renderedSize: CGSize(width: 520, height: 150))

        XCTAssertGreaterThan(bubbleBounds.minX, 60, "Wrapped user bubble should leave leading space.")
        XCTAssertLessThan(bubbleBounds.width, 470, "Wrapped user bubble should remain capped below the transcript width.")
    }

    private func render<V: View>(_ view: V, size: CGSize) -> NSBitmapImageRep {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Could not create bitmap for transcript render.")
            return NSBitmapImageRep()
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    private func tintedBounds(in image: NSBitmapImageRep, renderedSize: CGSize) -> CGRect {
        var minX = image.pixelsWide
        var maxX = 0
        var minY = image.pixelsHigh
        var maxY = 0

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.98,
                   color.greenComponent < 0.96,
                   color.blueComponent < 0.96 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        XCTAssertLessThan(minX, image.pixelsWide, "Rendered transcript should contain a tinted user bubble.")
        let scale = CGFloat(image.pixelsWide) / renderedSize.width
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        ).applying(CGAffineTransform(scaleX: 1 / scale, y: 1 / scale))
    }
}
