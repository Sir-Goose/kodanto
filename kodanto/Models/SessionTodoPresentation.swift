import Foundation

enum SessionTodoStatus: String, Hashable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
    case unknown

    init(rawStatus: String) {
        self = SessionTodoStatus(rawValue: rawStatus) ?? .unknown
    }

    var isClosed: Bool {
        self == .completed || self == .cancelled
    }

    var isCompleted: Bool {
        self == .completed
    }
}

enum SessionTodoPresentation {
    static func status(for todo: OpenCodeTodo) -> SessionTodoStatus {
        SessionTodoStatus(rawStatus: todo.status)
    }

    static func completedCount(in todos: [OpenCodeTodo]) -> Int {
        todos.reduce(into: 0) { count, todo in
            if status(for: todo).isCompleted {
                count += 1
            }
        }
    }

    static func allClosed(in todos: [OpenCodeTodo]) -> Bool {
        !todos.isEmpty && todos.allSatisfy { status(for: $0).isClosed }
    }

    static func previewTodo(in todos: [OpenCodeTodo]) -> OpenCodeTodo? {
        if let inProgress = todos.first(where: { status(for: $0) == .inProgress }) {
            return inProgress
        }
        if let pending = todos.first(where: { status(for: $0) == .pending }) {
            return pending
        }
        if let completed = todos.last(where: { status(for: $0) == .completed }) {
            return completed
        }
        return todos.first
    }
}

enum SessionTodoDockVisibility: Equatable {
    case hidden
    case visible
    case closing

    var isVisible: Bool {
        self != .hidden
    }
}

enum SessionTodoDockEvent: Equatable {
    case todosChanged([OpenCodeTodo])
    case closeTimerFired
}

enum SessionTodoDockEffect: Equatable {
    case none
    case startCloseTimer(TimeInterval)
    case cancelCloseTimer
}

enum SessionTodoDockStateMachine {
    static let closeDelay: TimeInterval = 0.4

    static func reduce(
        state: SessionTodoDockVisibility,
        event: SessionTodoDockEvent
    ) -> (state: SessionTodoDockVisibility, effect: SessionTodoDockEffect) {
        switch event {
        case .closeTimerFired:
            if state == .closing {
                return (.hidden, .none)
            }
            return (state, .none)

        case .todosChanged(let todos):
            if todos.isEmpty {
                if state == .closing {
                    return (.hidden, .cancelCloseTimer)
                }
                return (.hidden, .none)
            }

            let allClosed = SessionTodoPresentation.allClosed(in: todos)
            if !allClosed {
                switch state {
                case .hidden, .visible:
                    return (.visible, .none)
                case .closing:
                    return (.visible, .cancelCloseTimer)
                }
            }

            switch state {
            case .visible:
                return (.closing, .startCloseTimer(closeDelay))
            case .hidden:
                // Avoid flashing the dock when opening sessions whose todos are already closed.
                return (.hidden, .none)
            case .closing:
                return (.closing, .none)
            }
        }
    }
}
