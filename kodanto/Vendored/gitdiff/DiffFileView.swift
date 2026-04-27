import SwiftUI

struct DiffFileView: View {
  let file: DiffFile

  @Environment(\.diffConfiguration) private var configuration

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if configuration.showFileHeaders {
        HStack {
          Image(systemName: "doc.text")
            .foregroundColor(configuration.theme.fileHeaderText)

          Text(file.displayName)
            .font(.system(.headline, design: configuration.fontFamily))
            .fontWeight(.bold)
            .foregroundColor(configuration.theme.fileHeaderText)

          Spacer()

          if file.isBinary {
            Text("Binary file")
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.2))
              .cornerRadius(4)
          }
        }
        .padding()
        .background(configuration.theme.fileHeaderBackground)
      }

      if file.isBinary {
        Text("Binary file not shown")
          .font(.system(size: configuration.fontSize, design: configuration.fontFamily))
          .foregroundColor(.secondary)
          .padding()
      } else {
        ForEach(file.hunks) { hunk in
          VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
              .font(.system(.caption, design: configuration.fontFamily))
              .foregroundColor(configuration.theme.headerText)
              .padding(.horizontal)
              .padding(.vertical, 4)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(configuration.theme.headerBackground)

            LazyVStack(spacing: configuration.lineSpacing.value) {
              ForEach(hunk.lines) { line in
                DiffLineView(line: line)
              }
            }
            .background(configuration.theme.contextBackground)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .background(configuration.theme.contextBackground)
    .cornerRadius(6)
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
    )
  }
}
