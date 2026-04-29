import SwiftUI

struct FileTreeRowView: View {
    @Bindable var store: FileBrowserStore
    let onSelectFile: (FileNode) -> Void

    @State private var hoveredPath: String?

    private var visibleRows: [FileTreeRow] {
        buildVisibleRows()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(visibleRows) { row in
                    rowView(row)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func rowView(_ row: FileTreeRow) -> some View {
        if row.node.isDirectory {
            directoryRow(row)
        } else {
            fileRow(row)
        }
    }

    private func directoryRow(_ row: FileTreeRow) -> some View {
        Button {
            Task { await store.toggleDirectory(row.node.path) }
        } label: {
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    chevron(row: row)
                    icon(for: row)
                }
                .frame(width: 28, alignment: .leading)

                Text(row.node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if store.isLoading(path: row.node.path) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }
            .padding(.leading, CGFloat(row.depth * 14))
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(hoveredPath == row.node.path ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hoveredPath = $0 ? row.node.path : nil }
    }

    private func fileRow(_ row: FileTreeRow) -> some View {
        Button {
            onSelectFile(row.node)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)

                Text(row.node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth * 14) + 12)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(hoveredPath == row.node.path ? Color.secondary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hoveredPath = $0 ? row.node.path : nil }
    }

    @ViewBuilder
    private func chevron(row: FileTreeRow) -> some View {
        if row.isExpanded {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func icon(for row: FileTreeRow) -> some View {
        Image(systemName: row.isExpanded ? "folder.fill" : "folder")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func buildVisibleRows() -> [FileTreeRow] {
        var rows: [FileTreeRow] = []
        addChildren(of: "", depth: 0, rows: &rows)
        return rows
    }

    private func addChildren(of path: String, depth: Int, rows: inout [FileTreeRow]) {
        let children = store.children(of: path)

        for node in children {
            let isExpanded = node.isDirectory && store.isExpanded(path: node.path)
            let isLoading = node.isDirectory && store.isLoading(path: node.path)

            rows.append(FileTreeRow(node: node, depth: depth, isExpanded: isExpanded, isLoading: isLoading))

            if node.isDirectory, isExpanded {
                addChildren(of: node.path, depth: depth + 1, rows: &rows)
            }
        }
    }
}

private struct FileTreeRow: Identifiable {
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool

    var id: String { node.path }
}
