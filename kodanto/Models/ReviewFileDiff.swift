import Foundation

struct ReviewFileDiff: Identifiable, Hashable {
    let filePath: String
    let patch: String
    let before: String
    let after: String
    let additions: Int
    let deletions: Int
    let status: DiffStatus

    enum DiffStatus: String {
        case added
        case deleted
        case modified
    }

    var id: String { filePath }

    var filename: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var directory: String {
        let dir = (filePath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }
}

extension ReviewFileDiff {
    init(patchFile: ToolPatchFile) {
        self.filePath = patchFile.movePath ?? patchFile.filePath
        self.patch = patchFile.diff
        self.before = patchFile.before
        self.after = patchFile.after
        self.additions = patchFile.additions
        self.deletions = patchFile.deletions
        switch patchFile.type {
        case "add":
            self.status = .added
        case "delete":
            self.status = .deleted
        default:
            self.status = .modified
        }
    }

    init(fileDiff: ToolFileDiff) {
        self.filePath = fileDiff.file
        self.patch = DiffParserService.computeDiff(from: fileDiff.before, to: fileDiff.after, filePath: fileDiff.file)
        self.before = fileDiff.before
        self.after = fileDiff.after
        self.additions = fileDiff.additions
        self.deletions = fileDiff.deletions
        self.status = .modified
    }
}