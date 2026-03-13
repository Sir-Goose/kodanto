import SwiftUI

struct TerminalPanelView: View {
    @Bindable var model: KodantoAppModel
    let availableHeight: CGFloat

    @State private var dragStartHeight: CGFloat?

    private static let minimumHeight: CGFloat = 140

    private var maximumHeight: CGFloat {
        max(Self.minimumHeight, availableHeight * 0.6)
    }

    private var resolvedHeight: CGFloat {
        TerminalPanelSizing.clampedHeight(
            preferredHeight: CGFloat(model.terminalPanelHeight),
            availableHeight: availableHeight,
            minimumHeight: Self.minimumHeight
        )
    }

    var body: some View {
        Group {
            if model.isTerminalPanelOpen {
                VStack(spacing: 0) {
                    resizeHandle
                    terminalContent
                }
                .frame(maxWidth: .infinity)
                .frame(height: resolvedHeight, alignment: .top)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(alignment: .top) {
                    Divider()
                }
                .clipped()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    model.ensureTerminalConnectedIfNeeded()
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.isTerminalPanelOpen)
    }

    private var resizeHandle: some View {
        ZStack {
            Color.clear
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 44, height: 4)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = resolvedHeight
                    }

                    let base = dragStartHeight ?? resolvedHeight
                    let next = min(max(base - value.translation.height, Self.minimumHeight), maximumHeight)
                    model.setTerminalPanelHeight(Double(next))
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
        .help("Drag to resize terminal")
    }

    @ViewBuilder
    private var terminalContent: some View {
        if !model.canShowTerminal {
            placeholder(text: "Select a project to use the terminal.")
        } else if let message = model.terminalStore.activeErrorMessage {
            VStack(spacing: 10) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    model.retryTerminalConnection()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let pty = model.terminalStore.activePTY {
            ZStack {
                TerminalWebView(
                    sessionID: pty.id,
                    outputRevision: model.terminalStore.activeOutputRevision,
                    consumeOutput: { model.consumeTerminalOutputChunks() },
                    onInput: { value in
                        model.sendTerminalInput(value)
                    },
                    onResize: { rows, cols in
                        model.updateTerminalSize(rows: rows, cols: cols)
                    }
                )
                .id(pty.id)

                if model.terminalStore.activePhase == .loading || model.terminalStore.activePhase == .connecting {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Connecting terminal...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.terminalStore.activePhase == .loading || model.terminalStore.activePhase == .connecting {
            VStack(spacing: 10) {
                ProgressView()
                Text("Starting terminal...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder(text: "Open the terminal to run shell commands for this workspace.")
        }
    }

    private func placeholder(text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
    }
}

enum TerminalPanelSizing {
    static func clampedHeight(preferredHeight: CGFloat, availableHeight: CGFloat, minimumHeight: CGFloat) -> CGFloat {
        let maxHeight = max(minimumHeight, availableHeight * 0.6)
        return min(max(preferredHeight, minimumHeight), maxHeight)
    }
}
