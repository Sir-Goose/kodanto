import SwiftUI

struct ComposerControlsRow: View {
    @Bindable var model: KodantoAppModel
    @State private var isHovered = false
    @State private var isShowingPicker = false

    var body: some View {
        HStack(spacing: 10) {
            if model.isLoadingModels {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedModel = model.selectedModel {
                Button {
                    isShowingPicker.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(selectedModel.modelName)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(selectedModel.providerName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(modelPickerBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                }
                .buttonStyle(.plain)
                .help(selectedModel.id)
                .accessibilityIdentifier("model-picker-button")
                .onHover { hovering in
                    isHovered = hovering
                }
                .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
                    ModelPickerPopover(
                        groups: model.availableModelGroups,
                        selectedModelID: selectedModel.id
                    ) { option in
                        model.selectModel(option.id)
                        isShowingPicker = false
                    }
                }

                ThinkingEffortPicker(model: model)
            } else if let modelLoadError = model.modelLoadError {
                Text(modelLoadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No models available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AgentPicker(model: model)
            PermissionAutoAcceptToggle(model: model)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34, alignment: .center)
    }

    private var modelPickerBackground: Color {
        if isShowingPicker {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

struct AgentPicker: View {
    @Bindable var model: KodantoAppModel
    @State private var isHovered = false
    @State private var isShowingPicker = false

    private var selectionLabel: String {
        model.selectedPromptAgentName ?? "Default Agent"
    }

    private var hasAgents: Bool {
        !model.availablePromptAgents.isEmpty
    }

    private var helpText: String {
        if hasAgents {
            return "Select agent"
        }
        return "No primary agents available. Prompts will use the server default agent."
    }

    private var selectionIconSystemName: String {
        AgentModeIconResolver.systemImageName(
            selectedAgentName: model.selectedPromptAgentName,
            availableAgents: model.availablePromptAgents
        )
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectionIconSystemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(selectionLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasAgents)
        .help(helpText)
        .accessibilityIdentifier("agent-picker")
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            AgentPickerPopover(
                agents: model.availablePromptAgents,
                selectedAgentName: model.selectedPromptAgentName
            ) { agentName in
                model.selectPromptAgent(agentName)
                isShowingPicker = false
            }
        }
    }

    private struct AgentPickerPopover: View {
        let agents: [OpenCodeAgent]
        let selectedAgentName: String?
        let onSelect: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(agents, id: \.id) { agent in
                    Button {
                        onSelect(agent.name)
                    } label: {
                        optionRow(agent, isSelected: selectedAgentName == agent.name)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(width: 240, alignment: .leading)
        }

        @ViewBuilder
        private func optionRow(_ agent: OpenCodeAgent, isSelected: Bool) -> some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.callout.weight(isSelected ? .medium : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let description = agent.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var backgroundColor: Color {
        isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

enum AgentModeIconResolver {
    enum Kind {
        case build
        case plan
        case other
    }

    static func systemImageName(selectedAgentName: String?, availableAgents: [OpenCodeAgent]) -> String {
        switch classify(selectedAgentName: selectedAgentName, availableAgents: availableAgents) {
        case .build:
            return "hammer"
        case .plan:
            return "checklist"
        case .other:
            return "person.crop.circle"
        }
    }

    static func classify(selectedAgentName: String?, availableAgents: [OpenCodeAgent]) -> Kind {
        let normalizedSelectedName = normalized(selectedAgentName)
        let selectedAgent = normalizedSelectedName.flatMap { selectedName in
            availableAgents.first { normalized($0.name) == selectedName }
        }
        let normalizedSelectedMode = normalized(selectedAgent?.mode)

        if normalizedSelectedName == "build" || normalizedSelectedMode == "build" {
            return .build
        }

        if normalizedSelectedName == "plan" || normalizedSelectedMode == "plan" {
            return .plan
        }

        return .other
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}

struct PermissionAutoAcceptToggle: View {
    @Bindable var model: KodantoAppModel

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.isPermissionAutoAcceptEnabled },
            set: { model.setPermissionAutoAccept($0) }
        )
    }

    var body: some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: "shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Full Access")
            }
        }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption.weight(.medium))
            .fixedSize()
            .disabled(!model.canTogglePermissionAutoAccept)
            .help(model.isPermissionAutoAcceptEnabled ? "Stop auto-accepting permission requests" : "Auto-accept permission requests for this session")
            .opacity(model.canTogglePermissionAutoAccept ? 1 : 0.45)
            .accessibilityIdentifier("permission-auto-accept-toggle")
    }
}

struct ThinkingEffortPicker: View {
    @Bindable var model: KodantoAppModel
    @State private var isHovered = false
    @State private var isShowingPicker = false

    private var selectionLabel: String {
        model.selectedPromptVariant ?? "Default"
    }

    private var hasVariants: Bool {
        !model.selectedModelVariants.isEmpty
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(selectionLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!hasVariants)
        .help("Thinking effort")
        .accessibilityIdentifier("thinking-effort-picker")
        .onHover { hovering in
            isHovered = hovering
        }
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            ThinkingEffortPickerPopover(
                variants: model.selectedModelVariants,
                selectedVariant: model.selectedPromptVariant
            ) { variant in
                model.selectModelVariant(variant)
                isShowingPicker = false
            }
        }
    }

    private struct ThinkingEffortPickerPopover: View {
        let variants: [String]
        let selectedVariant: String?
        let onSelect: (String?) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    onSelect(nil)
                } label: {
                    optionRow("Default", isSelected: selectedVariant == nil)
                }
                .buttonStyle(.plain)

                ForEach(variants, id: \.self) { variant in
                    Button {
                        onSelect(variant)
                    } label: {
                        optionRow(variant, isSelected: selectedVariant == variant)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(width: 180, alignment: .leading)
        }

        @ViewBuilder
        private func optionRow(_ title: String, isSelected: Bool) -> some View {
            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var backgroundColor: Color {
        isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

struct ModelPickerPopover: View {
    let groups: [OpenCodeModelProviderGroup]
    let selectedModelID: String
    let onSelect: (OpenCodeModelOption) -> Void

    @State private var expandedProviderID: String?

    init(
        groups: [OpenCodeModelProviderGroup],
        selectedModelID: String,
        onSelect: @escaping (OpenCodeModelOption) -> Void
    ) {
        self.groups = groups
        self.selectedModelID = selectedModelID
        self.onSelect = onSelect
        _expandedProviderID = State(initialValue: groups.first(where: { group in
            group.models.contains(where: { $0.id == selectedModelID })
        })?.id ?? groups.first?.id)
    }

    private var selectedProviderID: String? {
        groups.first(where: { group in
            group.models.contains(where: { $0.id == selectedModelID })
        })?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            if expandedProviderID == group.id {
                                expandedProviderID = nil
                            } else {
                                expandedProviderID = group.id
                            }
                        } label: {
                            ModelPickerProviderRow(
                                group: group,
                                isExpanded: expandedProviderID == group.id,
                                isSelected: selectedProviderID == group.id
                            )
                        }
                        .buttonStyle(.plain)

                        if expandedProviderID == group.id {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(group.models) { option in
                                    Button {
                                        onSelect(option)
                                    } label: {
                                        ModelPickerOptionRow(
                                            option: option,
                                            isSelected: option.id == selectedModelID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 300, height: 320)
        .accessibilityIdentifier("model-picker-popover")
    }
}

struct ModelPickerProviderRow: View {
    let group: OpenCodeModelProviderGroup
    let isExpanded: Bool
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 12)

            Text(group.providerName)
                .font(.callout.weight(isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}

struct ModelPickerOptionRow: View {
    let option: OpenCodeModelOption
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(option.modelName)
                .font(.callout.weight(isSelected ? .medium : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        return isHovered ? Color.secondary.opacity(0.08) : .clear
    }
}
