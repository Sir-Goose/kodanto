import SwiftUI

struct SlashCommandPopover: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void
    let onHover: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                emptyStateView
            } else {
                commandListView
            }
        }
        .frame(maxHeight: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
    }
    
    private var emptyStateView: some View {
        Text("No commands found")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }
    
    private var commandListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        SlashCommandRow(
                            command: command,
                            isSelected: index == selectedIndex,
                            onSelect: { onSelect(command) },
                            onHover: { onHover(index) }
                        )
                        .id(command.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0 && newIndex < commands.count {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(commands[newIndex].id, anchor: .center)
                    }
                }
            }
        }
    }
}

struct SlashCommandRow: View {
    let command: SlashCommand
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("/\(command.trigger)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        if let description = command.description {
                            Text(description)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                if let keybind = command.keybind {
                    Text(keybind)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
    }
}

#Preview {
    SlashCommandPopover(
        commands: SlashCommand.builtinCommands,
        selectedIndex: 0,
        onSelect: { command in
            print("Selected: \(command.id)")
        },
        onHover: { index in
            print("Hovered: \(index)")
        }
    )
    .frame(width: 350)
    .padding()
}