import AppKit
import SwiftUI

struct SessionQuestionDockView: View {
    @Bindable var model: KodantoAppModel
    let request: OpenCodeQuestionRequest

    @State private var draftModel: SessionQuestionDraftModel

    private static let customEditorFont = NSFont.systemFont(ofSize: 14)
    private static let customEditorInset = NSSize(width: 0, height: 2)

    init(model: KodantoAppModel, request: OpenCodeQuestionRequest) {
        self.model = model
        self.request = request
        _draftModel = State(initialValue: SessionQuestionDraftModel(request: request))
    }

    private var customEditorMaxHeight: CGFloat {
        120
    }

    private var customEditorMinimumHeight: CGFloat {
        24
    }

    var body: some View {
        if draftModel.hasQuestions {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let currentQuestion = draftModel.currentQuestion {
                    bodyContent(for: currentQuestion)
                }

                if let submissionError = draftModel.submissionError, !submissionError.isEmpty {
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
            .onChange(of: request.id) { _, _ in
                draftModel = SessionQuestionDraftModel(request: request)
            }
            .onChange(of: request.questions) { _, _ in
                draftModel = SessionQuestionDraftModel(request: request)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Question")
                        .font(.headline)
                    Text(draftModel.summaryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(Array(draftModel.questions.enumerated()), id: \.offset) { index, _ in
                    Button {
                        draftModel.jump(to: index)
                    } label: {
                        Capsule(style: .continuous)
                            .fill(progressFill(for: index))
                            .frame(height: 6)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(progressStroke(for: index), lineWidth: index == draftModel.currentIndex ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(draftModel.isSending)
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

                Text(draftModel.currentQuestionAllowsMultiple ? "Choose one or more answers." : "Choose one answer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                    QuestionAnswerOptionRow(
                        label: option.label,
                        description: option.description,
                        isSelected: draftModel.currentAnswers.contains(option.label),
                        allowsMultiple: draftModel.currentQuestionAllowsMultiple,
                        isDisabled: draftModel.isSending,
                        action: {
                            draftModel.selectSuggestedAnswer(option.label)
                        }
                    )
                }

                if draftModel.currentQuestionAllowsCustom {
                    customAnswerRow
                }
            }
        }
    }

    private var customAnswerRow: some View {
        QuestionAnswerRowContainer(
            isSelected: draftModel.isCurrentCustomEnabled,
            allowsMultiple: draftModel.currentQuestionAllowsMultiple,
            isDisabled: draftModel.isSending,
            controlAction: { draftModel.toggleCustomAnswer() }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Type your own answer")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                if draftModel.isEditingCustomAnswer {
                    AutoSizingPromptEditor(
                        text: Binding(
                            get: { draftModel.currentCustomValue },
                            set: { draftModel.updateCustomAnswer($0) }
                        ),
                        measuredHeight: Binding(
                            get: { draftModel.customEditorHeight },
                            set: { draftModel.customEditorHeight = $0 }
                        ),
                        font: Self.customEditorFont,
                        textInset: Self.customEditorInset,
                        maxHeight: customEditorMaxHeight
                    ) {
                        draftModel.commitCustomAnswerEditing()
                    }
                    .frame(height: max(customEditorMinimumHeight, draftModel.customEditorHeight))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .onKeyPress(.escape, phases: .down) { _ in
                        draftModel.isEditingCustomAnswer = false
                        return .handled
                    }
                } else {
                    Text(draftModel.currentCustomValue.isEmpty ? "Write an answer..." : draftModel.currentCustomValue)
                        .font(.caption)
                        .foregroundStyle(draftModel.currentCustomValue.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        } action: {
            draftModel.openCustomAnswerEditor()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Dismiss", role: .destructive) {
                draftModel.reject {
                    try await model.submitQuestionRejection(request)
                }
            }
            .disabled(draftModel.isSending)

            Spacer(minLength: 0)

            if draftModel.canGoBack {
                Button("Back") {
                    draftModel.goBack()
                }
                .disabled(draftModel.isSending)
            }

            Button(draftModel.isLastQuestion ? "Submit" : "Next") {
                draftModel.advance { answers in
                    try await model.submitQuestionAnswers(request, answers: answers)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draftModel.isSending)
        }
    }

    private func progressFill(for index: Int) -> Color {
        if index == draftModel.currentIndex {
            return .accentColor
        }
        if draftModel.progressFill(for: index) {
            return Color.accentColor.opacity(0.45)
        }
        return Color.secondary.opacity(0.18)
    }

    private func progressStroke(for index: Int) -> Color {
        index == draftModel.currentIndex ? Color.accentColor.opacity(0.45) : .clear
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
