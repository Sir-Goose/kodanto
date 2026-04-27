import SwiftUI

struct DiffViewer: View {
    let diffText: String

    var body: some View {
        DiffRenderer(diffText: diffText)
            .diffTheme(.kodanto)
            .diffLineNumbers(true)
            .diffFont(size: 11, weight: .regular, design: .monospaced)
            .diffLineSpacing(.comfortable)
            .diffWordWrap(false)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

struct DiffStatsBadge: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        if additions > 0 || deletions > 0 {
            HStack(spacing: 6) {
                if additions > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                        Text("\(additions)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.green)
                }
                if deletions > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "minus")
                            .font(.caption2.weight(.bold))
                        Text("\(deletions)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }
}