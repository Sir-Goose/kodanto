import Foundation
import Observation

@MainActor
@Observable
final class LiveSyncCoordinator {
    private let apiFactory: OpenCodeAPIServiceFactory
    private let sseStreamProvider: OpenCodeSSEStreamProviding
    private let clock: AppClock
    private let reconnectDelay: Duration = .milliseconds(250)

    private var globalEventTask: Task<Void, Never>?
    private var heartbeatWatchdogTask: Task<Void, Never>?
    private var tracker = LiveSyncTracker()

    var lastSSEError: String?

    init(
        apiFactory: OpenCodeAPIServiceFactory,
        sseStreamProvider: OpenCodeSSEStreamProviding,
        clock: AppClock
    ) {
        self.apiFactory = apiFactory
        self.sseStreamProvider = sseStreamProvider
        self.clock = clock
    }

    var state: LiveSyncTracker.State {
        tracker.state
    }

    var reconnectCount: Int {
        tracker.reconnectCount
    }

    var lastEventAt: Date {
        tracker.lastEventAt
    }

    var isActive: Bool {
        tracker.state.isRunning
    }

    func start(
        for profile: ServerProfile,
        refresh: @escaping @MainActor (OpenCodeAPIService) async throws -> Void,
        handleEvent: @escaping @MainActor (OpenCodeGlobalEvent) -> Void
    ) {
        globalEventTask?.cancel()
        heartbeatWatchdogTask?.cancel()
        tracker.start(now: clock.now)
        lastSSEError = nil

        globalEventTask = Task { [weak self] in
            await self?.runStreamLoop(
                profile: profile,
                refresh: refresh,
                handleEvent: handleEvent
            )
        }
    }

    func stop() {
        globalEventTask?.cancel()
        globalEventTask = nil
        stopHeartbeatWatchdog()
        tracker.stop()
    }

    private func runStreamLoop(
        profile: ServerProfile,
        refresh: @escaping @MainActor (OpenCodeAPIService) async throws -> Void,
        handleEvent: @escaping @MainActor (OpenCodeGlobalEvent) -> Void
    ) async {
        let client = apiFactory.makeService(profile: profile)

        while !Task.isCancelled {
            do {
                startHeartbeatWatchdog(
                    for: profile,
                    refresh: refresh,
                    handleEvent: handleEvent
                )

                for try await event in sseStreamProvider.streamGlobalEvents(for: profile) {
                    if Task.isCancelled { return }
                    let shouldRefresh = tracker.receiveEvent(event, now: clock.now)
                    if shouldRefresh {
                        try await refresh(client)
                    }
                    handleEvent(event)
                }

                if !Task.isCancelled {
                    markReconnectNeeded("Live sync stream ended. Reconnecting...")
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                markReconnectNeeded(error.localizedDescription)
            }

            stopHeartbeatWatchdog()
            if Task.isCancelled { return }
            tracker.start(now: clock.now)
            try? await clock.sleep(for: reconnectDelay)
        }
    }

    private func startHeartbeatWatchdog(
        for profile: ServerProfile,
        refresh: @escaping @MainActor (OpenCodeAPIService) async throws -> Void,
        handleEvent: @escaping @MainActor (OpenCodeGlobalEvent) -> Void
    ) {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard tracker.state.isRunning else { continue }
                guard tracker.isHeartbeatTimedOut(now: clock.now) else { continue }
                markReconnectNeeded("Heartbeat timed out")
                globalEventTask?.cancel()
                start(for: profile, refresh: refresh, handleEvent: handleEvent)
                return
            }
        }
    }

    private func stopHeartbeatWatchdog() {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = nil
    }

    private func markReconnectNeeded(_ reason: String) {
        lastSSEError = reason
        tracker.markReconnectNeeded(reason: reason)
    }
}
