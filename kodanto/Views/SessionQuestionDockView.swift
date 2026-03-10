import AppKit
import SwiftUI

struct SessionQuestionDockView: View {
    @Bindable var model: KodantoAppModel
    let request: OpenCodeQuestionRequest

    @State private var currentIndex = 0
    @State private var answers: [[String]] = []
    @State private var customValues: [String] = []
    @State private var customEnabled: [Bool] = []
    @State private var isEditingCustomAnswer = false
    @State private var isSending = false
    @State private var submissionError: String?
    @State private var customEditorHeight: CGFloat = 0

    private static let customEditorFont = NSFont.systemFont(ofSize: 14)
    private static let customEditorInset = NSSize(width: 0, height: 2)

    private var questions: [OpenCodeQuestionRequest.Question] {
        request.questions
    }

    private var totalQuestions: Int {
        questions.count
    }

    private var hasQuestions: Bool {
        !questions.isEmpty
    }

    private var currentQuestion: OpenCodeQuestionRequest.Question? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    private var currentAnswers: [String] {
        answers[safe: currentIndex] ?? []
    }

    private var currentCustomValue: String {
        customValues[safe: currentIndex] ?? ""
    }

    private var isCurrentCustomEnabled: Bool {
        customEnabled[safe: currentIndex] ?? false
    }

    private var currentQuestionAllowsMultiple: Bool {
        currentQuestion?.multiple == true
    }

    private var currentQuestionAllowsCustom: Bool {
        currentQuestion?.custom != false
    }

    private var summaryTitle: String {
        "\(min(currentIndex + 1, totalQuestions)) of \(totalQuestions) questions"
    }

    private var isLastQuestion: Bool {
        currentIndex >= totalQuestions - 1
    }

    private var canGoBack: Bool {
        currentIndex > 0 && !isSending
    }

    private var customEditorMaxHeight: CGFloat {
        120
    }

    private var customEditorMinimumHeight: CGFloat {
        24
    }

    var body: some View {
        if hasQuestions {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let currentQuestion {
                    bodyContent(for: currentQuestion)
                }

                if let submissionError, !submissionError.isEmpty {
                    Text(submissionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                footer
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2))
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
            .onAppear {
                resetState()
            }
            .onChange(of: request.id) { _, _ in
                resetState()
            }
            .onChange(of: request.questions) { _, _ in
                resetState()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Question")
                        .font(.headline)
                    Text(summaryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, _ in
                    Button {
                        jump(to: index)
                    } label: {
                        Capsule(style: .continuous)
                            .fill(progressFill(for: index))
                            .frame(height: 6)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(progressStroke(for: index), lineWidth: index == currentIndex ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityLabel("Question \(index + 1)")
                }
            }
        }
    }

    private func bodyContent(for question: OpenCodeQuestionRequest.Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(question.header)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(question.question)
                    .font(.body.weight(.medium))

                Text(currentQuestionAllowsMultiple ? "Choose one or more answers." : "Choose one answer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                    QuestionAnswerOptionRow(
                        label: option.label,
                        description: option.description,
                        isSelected: currentAnswers.contains(option.label),
                        allowsMultiple: currentQuestionAllowsMultiple,
                        isDisabled: isSending,
                        action: {
                            selectSuggestedAnswer(option.label)
                        }
                    )
                }

                if currentQuestionAllowsCustom {
                    customAnswerRow
                }
            }
        }
    }

    private var customAnswerRow: some View {
        QuestionAnswerRowContainer(
            isSelected: isCurrentCustomEnabled,
            allowsMultiple: currentQuestionAllowsMultiple,
            isDisabled: isSending,
            controlAction: toggleCustomAnswer
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Type your own answer")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                if isEditingCustomAnswer {
                    AutoSizingPromptEditor(
                        text: Binding(
                            get: { currentCustomValue },
                            set: { updateCustomAnswer($0) }
                        ),
                        measuredHeight: $customEditorHeight,
                        font: Self.customEditorFont,
                        textInset: Self.customEditorInset,
                        maxHeight: customEditorMaxHeight
                    ) {
                        commitCustomAnswerEditing()
                    }
                    .frame(height: max(customEditorMinimumHeight, customEditorHeight))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .onKeyPress(.escape, phases: .down) { _ in
                        isEditingCustomAnswer = false
                        return .handled
                    }
                } else {
                    Text(currentCustomValue.isEmpty ? "Write an answer..." : currentCustomValue)
                        .font(.caption)
                        .foregroundStyle(currentCustomValue.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        } action: {
            openCustomAnswerEditor()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Dismiss", role: .destructive) {
                rejectRequest()
            }
            .disabled(isSending)

            Spacer(minLength: 0)

            if canGoBack {
                Button("Back") {
                    goBack()
                }
                .disabled(isSending)
            }

            Button(isLastQuestion ? "Submit" : "Next") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending)
        }
    }

    private func resetState() {
        currentIndex = 0
        answers = Array(repeating: [], count: totalQuestions)
        customValues = Array(repeating: "", count: totalQuestions)
        customEnabled = Array(repeating: false, count: totalQuestions)
        isEditingCustomAnswer = false
        isSending = false
        submissionError = nil
        customEditorHeight = 0
    }

    private func jump(to index: Int) {
        guard !isSending, questions.indices.contains(index) else { return }
        commitCustomAnswerEditing()
        currentIndex = index
        isEditingCustomAnswer = false
        submissionError = nil
    }

    private func goBack() {
        guard canGoBack else { return }
        commitCustomAnswerEditing()
        currentIndex -= 1
        isEditingCustomAnswer = false
        submissionError = nil
    }

    private func advance() {
        guard !isSending else { return }
        commitCustomAnswerEditing()
        submissionError = nil

        if isLastQuestion {
            submitAnswers()
        } else {
            currentIndex += 1
            isEditingCustomAnswer = false
        }
    }

    private func selectSuggestedAnswer(_ label: String) {
        guard !isSending else { return }

        if currentQuestionAllowsMultiple {
            if currentAnswers.contains(label) {
                setAnswersForCurrentQuestion(currentAnswers.filter { $0 != label })
            } else {
                setAnswersForCurrentQuestion(currentAnswers + [label])
            }
        } else {
            setAnswersForCurrentQuestion([label])
            setCustomEnabledForCurrentQuestion(false)
            isEditingCustomAnswer = false
        }

        submissionError = nil
    }

    private func toggleCustomAnswer() {
        guard !isSending else { return }

        if currentQuestionAllowsMultiple {
            let shouldEnable = !isCurrentCustomEnabled
            setCustomEnabledForCurrentQuestion(shouldEnable)
            if shouldEnable {
                isEditingCustomAnswer = true
                syncCurrentCustomAnswerIntoSelection()
            } else {
                removeCurrentCustomAnswerFromSelection()
                isEditingCustomAnswer = false
            }
        } else {
            setCustomEnabledForCurrentQuestion(true)
            isEditingCustomAnswer = true
            syncCurrentCustomAnswerIntoSelection()
        }

        submissionError = nil
    }

    private func openCustomAnswerEditor() {
        guard !isSending else { return }
        if !isCurrentCustomEnabled {
            setCustomEnabledForCurrentQuestion(true)
            syncCurrentCustomAnswerIntoSelection()
        }
        isEditingCustomAnswer = true
        submissionError = nil
    }

    private func updateCustomAnswer(_ value: String) {
        setCustomValueForCurrentQuestion(value)
        syncCurrentCustomAnswerIntoSelection()
    }

    private func commitCustomAnswerEditing() {
        guard isEditingCustomAnswer else { return }
        isEditingCustomAnswer = false
        syncCurrentCustomAnswerIntoSelection()
    }

    private func syncCurrentCustomAnswerIntoSelection() {
        guard isCurrentCustomEnabled else { return }

        let trimmedValue = currentCustomValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousValue = previousCustomAnswerValue()
        var updatedAnswers = currentAnswers.filter { $0 != previousValue }

        if !trimmedValue.isEmpty {
            if currentQuestionAllowsMultiple {
                if !updatedAnswers.contains(trimmedValue) {
                    updatedAnswers.append(trimmedValue)
                }
            } else {
                updatedAnswers = [trimmedValue]
            }
        }

        setAnswersForCurrentQuestion(updatedAnswers)
    }

    private func removeCurrentCustomAnswerFromSelection() {
        let previousValue = previousCustomAnswerValue()
        setAnswersForCurrentQuestion(currentAnswers.filter { $0 != previousValue })
    }

    private func previousCustomAnswerValue() -> String {
        currentCustomValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitAnswers() {
        let payload = answers.map { questionAnswers in
            questionAnswers.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        isSending = true
        submissionError = nil

        Task {
            do {
                try await model.submitQuestionAnswers(request, answers: payload)
            } catch {
                await MainActor.run {
                    isSending = false
                    submissionError = error.localizedDescription
                }
                return
            }

            await MainActor.run {
                isSending = false
            }
        }
    }

    private func rejectRequest() {
        guard !isSending else { return }
        isSending = true
        submissionError = nil

        Task {
            do {
                try await model.submitQuestionRejection(request)
            } catch {
                await MainActor.run {
                    isSending = false
                    submissionError = error.localizedDescription
                }
                return
            }

            await MainActor.run {
                isSending = false
            }
        }
    }

    private func setAnswersForCurrentQuestion(_ value: [String]) {
        guard answers.indices.contains(currentIndex) else { return }
        answers[currentIndex] = value
    }

    private func setCustomValueForCurrentQuestion(_ value: String) {
        guard customValues.indices.contains(currentIndex) else { return }
        customValues[currentIndex] = value
    }

    private func setCustomEnabledForCurrentQuestion(_ value: Bool) {
        guard customEnabled.indices.contains(currentIndex) else { return }
        customEnabled[currentIndex] = value
    }

    private func progressFill(for index: Int) -> Color {
        if index == currentIndex {
            return .accentColor
        }
        if let answer = answers[safe: index], !answer.isEmpty {
            return Color.accentColor.opacity(0.45)
        }
        return Color.secondary.opacity(0.18)
    }

    private func progressStroke(for index: Int) -> Color {
        index == currentIndex ? Color.accentColor.opacity(0.45) : .clear
    }
}

private struct QuestionAnswerOptionRow: View {
    let label: String
    let description: String
    let isSelected: Bool
    let allowsMultiple: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        QuestionAnswerRowContainer(
            isSelected: isSelected,
            allowsMultiple: allowsMultiple,
            isDisabled: isDisabled,
            controlAction: action
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } action: {
            action()
        }
    }
}

private struct QuestionAnswerRowContainer<Content: View>: View {
    let isSelected: Bool
    let allowsMultiple: Bool
    let isDisabled: Bool
    let controlAction: () -> Void
    @ViewBuilder let content: Content
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: controlAction) {
                    selectionMark
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }

    private var selectionMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: allowsMultiple ? 6 : 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1.4)
                .background(
                    RoundedRectangle(cornerRadius: allowsMultiple ? 6 : 9, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .frame(width: 18, height: 18)

            if isSelected {
                if allowsMultiple {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.top, 2)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }

        return isHovered ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.05)
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.35) : .clear
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
