import SwiftUI

struct FileBrowserPanel: View {
    @Bindable var store: FileBrowserStore
    let reviewDiffs: [ReviewFileDiff]
    @Binding var expandedFiles: Set<String>
    let onSelectFile: (FileNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 0) {
            tabButton(title: "Changes", tab: .changes)
            tabButton(title: "Files", tab: .files)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func tabButton(title: String, tab: FileBrowserTab) -> some View {
        Button {
            store.setTab(tab)
        } label: {
            Text(title)
                .font(.callout.weight(store.tab == tab ? .semibold : .regular))
                .foregroundStyle(store.tab == tab ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    store.tab == tab
                        ? Color.secondary.opacity(0.12)
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch store.tab {
        case .changes:
            changesTab
        case .files:
            filesTab
        }
    }

    @ViewBuilder
    private var changesTab: some View {
        if reviewDiffs.isEmpty {
            emptyChangesState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(reviewDiffs) { diff in
                        FileDiffCard(
                            diff: diff,
                            isExpanded: Binding(
                                get: { expandedFiles.contains(diff.filePath) },
                                set: { newValue in
                                    if newValue {
                                        expandedFiles.insert(diff.filePath)
                                    } else {
                                        expandedFiles.remove(diff.filePath)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(8)
            }
        }
    }

    @ViewBuilder
    private var filesTab: some View {
        if store.hasNodes {
            FileTreeRowView(store: store, onSelectFile: onSelectFile)
        } else if let error = store.loadError {
            errorState(error)
        } else {
            emptyFilesState
        }
    }

    private var emptyChangesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No changes yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No files loaded")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ error: FileBrowserStoreError) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
