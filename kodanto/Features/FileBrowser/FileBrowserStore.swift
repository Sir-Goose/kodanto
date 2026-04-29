import Foundation
import Observation

enum FileBrowserTab: Equatable {
    case changes
    case files
}

enum FileBrowserStoreError: LocalizedError, Equatable {
    case directoryNotFound
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Directory not found"
        case .loadFailed(let message):
            return message
        }
    }
}

@MainActor
@Observable
final class FileBrowserStore {
    private var apiService: OpenCodeAPIService?

    var tab: FileBrowserTab = .changes
    var expandedPaths: Set<String> = []
    var loadError: FileBrowserStoreError?

    private(set) var loadingPaths: Set<String> = []
    private var nodeCache: [String: [FileNode]] = [:]
    private var didAttemptInitialLoad = false

    init(apiService: OpenCodeAPIService? = nil) {
        self.apiService = apiService
    }

    func setTab(_ newTab: FileBrowserTab) {
        guard tab != newTab else { return }
        tab = newTab

        if newTab == .files, !didAttemptInitialLoad {
            didAttemptInitialLoad = true
            Task {
                try? await loadDirectory("")
            }
        }
    }

    func setAPIService(_ service: OpenCodeAPIService?) {
        apiService = service
    }

    var hasNodes: Bool {
        !nodeCache.isEmpty
    }

    var worktreeDirectory: String? {
        didSet {
            guard oldValue != worktreeDirectory else { return }
            if worktreeDirectory == nil {
                reset()
            }
        }
    }

    func children(of path: String) -> [FileNode] {
        nodeCache[path] ?? []
    }

    func isCached(path: String) -> Bool {
        nodeCache[path] != nil
    }

    func isLoading(path: String) -> Bool {
        loadingPaths.contains(path)
    }

    func isExpanded(path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func loadDirectory(_ path: String, force: Bool = false) async throws {
        guard let directory = worktreeDirectory else { return }
        guard let apiService else { return }

        if !force, nodeCache[path] != nil { return }

        loadingPaths.insert(path)
        loadError = nil
        defer { loadingPaths.remove(path) }

        do {
            let nodes = try await apiService.fileList(path: path, directory: directory)
            nodeCache[path] = nodes
        } catch {
            let storeError: FileBrowserStoreError
            if let apiError = error as? OpenCodeAPIError {
                storeError = .loadFailed(apiError.localizedDescription)
            } else {
                storeError = .loadFailed(error.localizedDescription)
            }
            loadError = storeError
            throw storeError
        }
    }

    func toggleDirectory(_ path: String) async {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
            return
        }

        expandedPaths.insert(path)

        if nodeCache[path] == nil {
            try? await loadDirectory(path)
        }
    }

    func expandToParent(of filePath: String) async throws {
        expandedPaths.insert("")

        let pathComponents = filePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        var cumulative = ""
        for component in pathComponents {
            cumulative = cumulative.isEmpty ? component : "\(cumulative)/\(component)"

            if !expandedPaths.contains(cumulative) {
                expandedPaths.insert(cumulative)
            }

            if nodeCache[cumulative] == nil {
                try? await loadDirectory(cumulative)
            }
        }
    }

    func refresh() async {
        guard worktreeDirectory != nil else { return }
        guard apiService != nil else { return }

        let previouslyLoaded = Set(nodeCache.keys)
        nodeCache.removeAll()

        for path in previouslyLoaded {
            try? await loadDirectory(path)
        }
    }

    func reset() {
        tab = .changes
        expandedPaths.removeAll()
        loadingPaths.removeAll()
        nodeCache.removeAll()
        loadError = nil
        didAttemptInitialLoad = false
        worktreeDirectory = nil
    }
}
