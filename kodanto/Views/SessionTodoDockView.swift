import SwiftUI

struct SessionTodoDockView: View {
    let todos: [OpenCodeTodo]

    @State private var isCollapsed = false
    @State private var visibility: SessionTodoDockVisibility = .hidden
    @State private var closeTimer: DispatchWorkItem?

    private var completedCount: Int {
        SessionTodoPresentation.completedCount(in: todos)
    }

    private var preview: OpenCodeTodo? {
        SessionTodoPresentation.previewTodo(in: todos)
    }

    var body: some View {
        Group {
            if visibility.isVisible {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    if !isCollapsed {
                        Divider()
                        todoList
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            apply(event: .todosChanged(todos))
        }
        .onChange(of: todos) { _, updatedTodos in
            apply(event: .todosChanged(updatedTodos))
        }
        .onDisappear {
            cancelCloseTimer()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(completedCount) of \(todos.count) tasks completed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isCollapsed, let preview {
                    Text(preview.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button {
                toggleCollapsed()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 180))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand tasks" : "Collapse tasks")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleCollapsed()
        }
    }

    private var todoList: some View {
        Group {
            if needsScrollableList {
                ScrollView {
                    todoRows
                }
                .frame(maxHeight: 170)
            } else {
                todoRows
            }
        }
    }

    private var todoRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                TodoRow(todo: todo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var needsScrollableList: Bool {
        todos.count > 6
    }

    private func toggleCollapsed() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isCollapsed.toggle()
        }
    }

    private func apply(event: SessionTodoDockEvent) {
        let transition = SessionTodoDockStateMachine.reduce(state: visibility, event: event)

        withAnimation(.easeInOut(duration: 0.18)) {
            visibility = transition.state
        }

        switch transition.effect {
        case .none:
            break
        case .cancelCloseTimer:
            cancelCloseTimer()
        case .startCloseTimer(let delay):
            startCloseTimer(after: delay)
        }
    }

    private func startCloseTimer(after delay: TimeInterval) {
        cancelCloseTimer()

        let workItem = DispatchWorkItem {
            apply(event: .closeTimerFired)
        }
        closeTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelCloseTimer() {
        closeTimer?.cancel()
        closeTimer = nil
    }
}

private struct TodoRow: View {
    let todo: OpenCodeTodo

    private var status: SessionTodoStatus {
        SessionTodoPresentation.status(for: todo)
    }

    private var isClosed: Bool {
        status == .completed || status == .cancelled
    }

    private var textColor: Color {
        isClosed ? .secondary : .primary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            TodoStatusIcon(status: status)
                .padding(.top, 2)

            Text(todo.content)
                .font(.callout)
                .strikethrough(isClosed, color: .secondary)
                .foregroundStyle(textColor)
                .opacity(status == .pending ? 0.94 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TodoStatusIcon: View {
    let status: SessionTodoStatus
    @State private var pulse = false

    var body: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .inProgress:
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.2)
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.2 : 0.75)
                    .opacity(pulse ? 0.95 : 0.55)
                    .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: pulse)
            }
            .onAppear {
                pulse = true
            }

        case .pending, .unknown:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
