import Foundation

enum ProjectDropPlacement: Equatable {
    case before
    case after
}

enum ProjectOrderResolver {
    static func deduplicatedProjectIDs(_ projectIDs: [String]) -> [String] {
        var seenIDs: Set<String> = []
        return projectIDs.filter { seenIDs.insert($0).inserted }
    }

    static func storedProjectReferences(for projects: [OpenCodeProject]) -> [String] {
        var seenReferences: Set<String> = []
        return projects.compactMap { project in
            let reference = projectIdentity(for: project)
            guard seenReferences.insert(reference).inserted else { return nil }
            return reference
        }
    }

    static func matchesProjectLocation(_ lhs: String, _ rhs: String) -> Bool {
        normalizedProjectLocation(lhs) == normalizedProjectLocation(rhs)
    }

    static func deduplicatedProjects(_ projects: [OpenCodeProject], preferredIDs: [String] = []) -> [OpenCodeProject] {
        let storedIndexes = Dictionary(uniqueKeysWithValues: deduplicatedProjectIDs(preferredIDs).enumerated().map { ($1, $0) })
        var bestProjectsByIdentity: [String: OpenCodeProject] = [:]
        var orderedIdentities: [String] = []

        for project in projects {
            let identity = projectIdentity(for: project)

            guard let existing = bestProjectsByIdentity[identity] else {
                orderedIdentities.append(identity)
                bestProjectsByIdentity[identity] = project
                continue
            }

            if prefers(project, over: existing, storedIndexes: storedIndexes) {
                bestProjectsByIdentity[identity] = project
            }
        }

        return orderedIdentities.compactMap { bestProjectsByIdentity[$0] }
    }

    static func orderedProjects(_ projects: [OpenCodeProject], storedIDs: [String]) -> [OpenCodeProject] {
        let orderedByRecency = deduplicatedProjects(projects, preferredIDs: storedIDs).sorted { lhs, rhs in
            if lhs.time.updated != rhs.time.updated {
                return lhs.time.updated > rhs.time.updated
            }

            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        guard !storedIDs.isEmpty else { return orderedByRecency }

        let storedIndexes = Dictionary(uniqueKeysWithValues: deduplicatedProjectIDs(storedIDs).enumerated().map { ($1, $0) })

        return orderedByRecency.sorted { lhs, rhs in
            let lhsStoredIndex = storedIndex(for: lhs, in: storedIndexes)
            let rhsStoredIndex = storedIndex(for: rhs, in: storedIndexes)

            switch (lhsStoredIndex, rhsStoredIndex) {
            case let (lhsIndex?, rhsIndex?) where lhsIndex != rhsIndex:
                return lhsIndex < rhsIndex
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.time.updated != rhs.time.updated {
                    return lhs.time.updated > rhs.time.updated
                }

                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        }
    }

    static func reorderedProjects(
        _ projects: [OpenCodeProject],
        movingProjectID: OpenCodeProject.ID,
        relativeTo targetProjectID: OpenCodeProject.ID,
        placement: ProjectDropPlacement
    ) -> [OpenCodeProject] {
        var reorderedProjects = deduplicatedProjects(projects)

        guard reorderedProjects.count > 1 else { return reorderedProjects }
        guard movingProjectID != targetProjectID else { return reorderedProjects }
        guard let sourceIndex = reorderedProjects.firstIndex(where: { $0.id == movingProjectID }) else { return reorderedProjects }
        guard let targetIndex = reorderedProjects.firstIndex(where: { $0.id == targetProjectID }) else { return reorderedProjects }

        let movedProject = reorderedProjects.remove(at: sourceIndex)

        var insertionIndex = targetIndex
        if placement == .after {
            insertionIndex += 1
        }
        if sourceIndex < insertionIndex {
            insertionIndex -= 1
        }

        reorderedProjects.insert(movedProject, at: max(0, min(insertionIndex, reorderedProjects.count)))
        return reorderedProjects
    }

    private static func projectIdentity(for project: OpenCodeProject) -> String {
        let normalizedWorktree = normalizedProjectLocation(project.worktree)
        if normalizedWorktree.isEmpty {
            return "id:\(project.id)"
        }

        return "worktree:\(normalizedWorktree)"
    }

    private static func normalizedProjectLocation(_ location: String) -> String {
        NSString(string: location).standardizingPath
    }

    private static func prefers(
        _ candidate: OpenCodeProject,
        over existing: OpenCodeProject,
        storedIndexes: [String: Int]
    ) -> Bool {
        let candidateStoredIndex = storedIndex(for: candidate, in: storedIndexes)
        let existingStoredIndex = storedIndex(for: existing, in: storedIndexes)

        switch (candidateStoredIndex, existingStoredIndex) {
        case let (candidateIndex?, existingIndex?) where candidateIndex != existingIndex:
            return candidateIndex < existingIndex
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if candidate.time.updated != existing.time.updated {
                return candidate.time.updated > existing.time.updated
            }

            return candidate.id.localizedCaseInsensitiveCompare(existing.id) == .orderedAscending
        }
    }

    private static func storedIndex(for project: OpenCodeProject, in storedIndexes: [String: Int]) -> Int? {
        let references = [projectIdentity(for: project), project.id]
        return references.compactMap { storedIndexes[$0] }.min()
    }
}
