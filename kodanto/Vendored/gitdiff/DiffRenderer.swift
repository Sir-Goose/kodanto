import SwiftUI

public struct DiffRenderer: View {
  let diffText: String

  @Environment(\.diffConfiguration) private var configuration

  @State private var parsedFiles: [DiffFile]? = nil

  public init(diffText: String) {
    self.diffText = diffText
  }

  public var body: some View {
    ScrollView {
      if parsedFiles == nil {
        VStack(spacing: 12) {
          ProgressView("Parsing diff…")
            .progressViewStyle(CircularProgressViewStyle())
            .tint(.accentColor)
          Text("Large diffs may take a moment.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let files = parsedFiles, files.isEmpty {
        VStack(spacing: 20) {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 50))
            .foregroundColor(.secondary)

          Text("No diff content to display")
            .font(.headline)
            .foregroundColor(.secondary)

          Text("The provided diff text appears to be empty or invalid.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let files = parsedFiles {
        VStack(spacing: 16) {
          ForEach(files) { file in
            DiffFileView(file: file)
          }
        }
        .padding()
      }
    }
    .background(Color.appBackground)
    .task(id: diffText) {
      self.parsedFiles = try? await DiffParser.parse(diffText)
    }
  }
}
