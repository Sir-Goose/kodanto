import SwiftUI

struct FileDiffCard: View {
    let diff: ReviewFileDiff
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: diff.status == .added ? "plus.circle.fill" : diff.status == .deleted ? "minus.circle.fill" : "pencil.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(diff.status == .added ? .green : diff.status == .deleted ? .red : Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(diff.filename)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !diff.directory.isEmpty {
                            Text(diff.directory)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }

                    Spacer(minLength: 4)

                    DiffStatsBadge(additions: diff.additions, deletions: diff.deletions)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                DiffViewer(diffText: diff.patch)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}