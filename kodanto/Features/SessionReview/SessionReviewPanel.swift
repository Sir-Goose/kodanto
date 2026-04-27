import SwiftUI

struct SessionReviewPanel: View {
    @Bindable var store: SessionReviewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Changes")
                .font(.headline)

            if store.visibleDiffCount > 0 {
                Text("(\(store.visibleDiffCount))")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !store.reviewDiffs.isEmpty {
                let allExpanded = store.expandedFiles.count == store.reviewDiffs.count
                Button(allExpanded ? "Collapse All" : "Expand All") {
                    if allExpanded {
                        store.collapseAll()
                    } else {
                        store.expandAll()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.reviewDiffs.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.reviewDiffs) { diff in
                        FileDiffCard(
                            diff: diff,
                            isExpanded: Binding(
                                get: { store.expandedFiles.contains(diff.filePath) },
                                set: { newValue in
                                    if newValue {
                                        store.expandedFiles.insert(diff.filePath)
                                    } else {
                                        store.expandedFiles.remove(diff.filePath)
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

    private var emptyState: some View {
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
        .frame(maxWidth: .infinity)
    }
}