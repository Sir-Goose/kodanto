import Foundation

enum PlaceholderProvider {
    static let prompts = [
        "Fix a TODO in the codebase",
        "What is the tech stack of this project?",
        "Fix broken tests",
        "Explain how authentication works",
        "Find and fix security vulnerabilities",
        "Add unit tests for the user service",
        "Refactor this function to be more readable",
        "What does this error mean?",
        "Help me debug this issue",
        "Generate API documentation",
        "Optimize database queries",
        "Add input validation",
        "Create a new component for...",
        "How do I deploy this project?",
        "Review my code for best practices",
        "Add error handling to this function",
        "Explain this regex pattern",
        "Convert this to TypeScript",
        "Add logging throughout the codebase",
        "What dependencies are outdated?",
        "Help me write a migration script",
        "Implement caching for this endpoint",
        "Add pagination to this list",
        "Create a CLI command for...",
        "How do environment variables work here?"
    ]

    static func randomPlaceholder(excluding current: String? = nil) -> String {
        let available = current.map { currentVal in
            prompts.filter { $0 != currentVal }
        } ?? prompts

        return available.randomElement() ?? prompts[0]
    }
}