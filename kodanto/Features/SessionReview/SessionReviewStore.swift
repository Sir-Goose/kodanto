import Observation
import Foundation

@MainActor
@Observable
final class SessionReviewStore {
    var isVisible = false
    var expandedFiles: Set<String> = []
    var reviewDiffs: [ReviewFileDiff] = []
    var lastSessionMessageCount: Int = 0

    var visibleDiffCount: Int {
        reviewDiffs.count
    }

    func toggleFile(_ filePath: String) {
        if expandedFiles.contains(filePath) {
            expandedFiles.remove(filePath)
        } else {
            expandedFiles.insert(filePath)
        }
    }

    func expandAll() {
        expandedFiles = Set(reviewDiffs.map(\.filePath))
    }

    func collapseAll() {
        expandedFiles.removeAll()
    }

    func updateDiffs(_ diffs: [ReviewFileDiff], messageCount: Int) {
        reviewDiffs = diffs
        lastSessionMessageCount = messageCount
    }
}