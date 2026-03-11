# Refactor Backlog

This document turns the maintainability review into an incremental PR plan.

## Goals

- Reduce the responsibility of `kodanto/App/KodantoAppModel.swift` without a big-bang rewrite.
- Add tests around the current behavior before moving the highest-risk logic.
- Introduce dependency seams so networking, SSE, sidecar, and persistence can be tested.
- Split the largest view files into feature-scoped units after the state boundaries are clearer.
- Keep the app shippable after every PR.

## Current Hotspots

- `kodanto/App/KodantoAppModel.swift` mixes app state, orchestration, persistence, transport calls, and event reduction.
- `kodanto/Views/MainView.swift` mixes shell layout, sidebar behavior, session detail flow, connection UI, and sheets.
- `kodanto/Views/TranscriptTurnView.swift` mixes transcript rendering and a full tool-rendering framework.
- `kodanto/Models/OpenCodeModels.swift` mixes transport payloads, event decoding, JSON helpers, and domain concerns.
- The project currently has no test target.

## Rules For Every PR

- Keep behavior changes out of structural refactors whenever possible.
- Keep `KodantoAppModel` as a temporary facade until the extracted stores settle.
- Preserve existing `UserDefaults` keys and persisted behavior unless a PR explicitly migrates them.
- Keep all async cancellation and stale-selection guards intact.
- Prefer one architectural move per PR so regressions are easy to isolate.

## Shared Verification

Use these checks after each PR, adjusting for whichever test targets exist at that point:

```sh
xcodebuild -project "kodanto.xcodeproj" -scheme "kodanto" -destination "platform=macOS" build
xcodebuild -project "kodanto.xcodeproj" -scheme "kodanto" -destination "platform=macOS" test
```

Manual smoke test list:

- Launch the app and connect to the selected profile.
- Switch between saved connections.
- Load projects and sessions.
- Create a session.
- Send a prompt and verify transcript updates.
- Verify permissions, questions, and todos appear correctly.
- Reorder projects and confirm the order persists across relaunch.

## Backlog Summary

| PR | Title | Depends On | Risk |
| --- | --- | --- | --- |
| 01 | Add tests and characterization coverage | None | Medium |
| 02 | Move persistence and helper types out of `KodantoAppModel` | 01 | Low |
| 03 | Introduce dependency container and service protocols | 02 | Medium |
| 04 | Extract permission and question workflows | 03 | Medium |
| 05 | Extract model catalog and composer state | 03 | Medium |
| 06 | Extract session detail and transcript state | 03, 05 | High |
| 07 | Extract workspace and selection state | 03, 06 | High |
| 08 | Extract live sync coordination and event reducers | 03, 06, 07 | High |
| 09 | Split transcript UI into feature files | 06 | Medium |
| 10 | Split main shell UI into feature files | 04, 05, 07, 09 | Medium |
| 11 | Optional module split into local packages | 08, 10 | High |

## PR 01 - Add Tests And Characterization Coverage

Goal: add a test target before the refactor touches behavior-heavy code.

Scope:

- Add a macOS unit test target to `kodanto.xcodeproj`.
- Add characterization tests for logic that is already fairly pure:
  - `OpenCodeSSEClient.EventParser`
  - `LiveSyncTracker`
  - `TranscriptTurn.build`
  - `SessionTodoDockStateMachine`
  - `ProjectOrderResolver`
- Add test fixtures/builders for sample projects, sessions, messages, parts, and events.

Acceptance criteria:

- A repeatable `xcodebuild ... test` path exists.
- Tests cover the current edge cases around event parsing, reconnect state, transcript grouping, todo dock transitions, and project ordering.
- No production behavior changes are introduced.

Notes:

- This PR will touch `kodanto.xcodeproj/project.pbxproj`; keep that change isolated.
- Prefer characterization tests first, then tighten behavior later once the seams are in place.

## PR 02 - Move Persistence And Helper Types Out Of `KodantoAppModel`

Goal: reduce file size and make future extractions easier without changing runtime behavior.

Scope:

- Move these types into dedicated files:
  - `ServerProfileStore`
  - `ModelSelectionStore`
  - `ModelVariantSelectionStore`
  - `PermissionAutoAcceptStore`
  - `ProjectOrderStore`
  - `ProjectOrderResolver`
  - `ProjectDropPlacement`
- Move generic helpers such as the `Array.moveItems` extension to a support file.
- Keep public APIs and persistence keys unchanged.

Suggested folders:

- `kodanto/Core/Persistence/`
- `kodanto/Core/Ordering/`
- `kodanto/Core/Support/`

Acceptance criteria:

- `KodantoAppModel` compiles with the extracted types imported from new files.
- Existing tests from PR 01 still pass unchanged.
- No UI or behavior regressions.

## PR 03 - Introduce Dependency Container And Service Protocols

Goal: make the app state testable without immediately rewriting the entire model.

Scope:

- Introduce a small app dependency container, for example `KodantoAppDependencies`.
- Add protocol seams for external integrations, such as:
  - API service / client factory
  - SSE stream provider
  - sidecar controller
  - profile persistence
  - model selection persistence
  - clock/sleeper for reconnect logic
- Update `KodantoAppModel` to accept dependencies with a default live implementation.
- Keep the existing live behavior as the default path used by `kodanto/App/kodantoApp.swift`.

Acceptance criteria:

- `KodantoAppModel` can be constructed in tests with fakes.
- No feature behavior changes for connect, refresh, send prompt, or live sync.
- New protocols are thin and reflect real seams, not one-method wrappers around every function.

Notes:

- Do not chase full abstraction purity here. The goal is just enough injection to unblock later PRs.

## PR 04 - Extract Permission And Question Workflows

Goal: remove request handling logic from the root app model and from the dock views.

Scope:

- Create a feature store for session requests, for example `SessionRequestStore`.
- Move request-related state and actions out of `KodantoAppModel`:
  - `permissions`
  - `questions`
  - auto-accept state
  - request submission methods
  - request upsert/remove reducers
- Replace raw reply strings such as `"reject"`, `"always"`, and `"once"` with a typed enum.
- Move workflow-heavy view state out of:
  - `kodanto/Views/SessionPermissionDockView.swift`
  - `kodanto/Views/SessionQuestionDockView.swift`
- Replace the question dock's parallel arrays with a typed draft model.

Acceptance criteria:

- Permission requests still appear, can be accepted/rejected, and auto-accept still prevents duplicate replies.
- Question flows still support multi-select and custom answers.
- Request-related views no longer own the async submission logic directly.

## PR 05 - Extract Model Catalog And Composer State

Goal: separate prompt composition and model selection from connection/workspace concerns.

Scope:

- Create feature state for:
  - available model groups
  - selected model
  - selected variant
  - model loading status/errors
  - draft prompt
- Move model catalog refresh and selection logic out of `KodantoAppModel`.
- Move prompt submission orchestration into a focused composer/model-selection feature.
- Preserve current per-profile selection persistence.

Acceptance criteria:

- Model selection still persists per profile.
- Prompt send failures still restore the draft text.
- Composer-related UI reads from a focused API rather than the entire app model surface.

## PR 06 - Extract Session Detail And Transcript State

Goal: isolate the highest-value feature state for transcript rendering and session detail updates.

Scope:

- Create `SessionDetailStore` or equivalent for:
  - `selectedSessionMessages`
  - `selectedSessionTurns`
  - `selectedSessionTranscriptRevision`
  - `sessionTodos`
  - message and part caches
- Extract pure reducers/helpers for:
  - replacing messages
  - upserting/removing messages
  - upserting/removing parts
  - applying part deltas
  - rebuilding transcript state
- Keep stale-selection guards intact when async loads return after a session switch.

Acceptance criteria:

- Transcript content remains identical for existing sessions.
- Todo updates still appear in the selected session.
- The revision signal still supports scroll behavior in the UI.

Notes:

- This is the first truly high-risk data-flow extraction. Lean on the PR 01 tests and add more here.

## PR 07 - Extract Workspace And Selection State

Goal: move project/session inventory and selection logic into its own feature boundary.

Scope:

- Create `WorkspaceStore` or `ProjectSessionStore` for:
  - projects
  - selected project/session
  - sessions by directory
  - session statuses by directory
  - sidebar indicators
  - loading-session state
- Move logic for:
  - project ordering and sanitizing
  - session loading and caching
  - selection reconciliation
  - session creation and selection updates
- Keep the root app model as a compatibility facade while the views are still migrating.

Acceptance criteria:

- Project ordering still persists and deduplicates correctly.
- Lazy session loading still works from the sidebar.
- Session creation and selection behavior remains unchanged.

## PR 08 - Extract Live Sync Coordination And Event Reducers

Goal: separate transport/reconnect logic from feature state mutation.

Scope:

- Introduce a `LiveSyncCoordinator` that owns:
  - stream startup
  - reconnect loop
  - heartbeat watchdog
  - last SSE error state
- Extract event reducers or routers for:
  - global events
  - directory-scoped events
- Route event mutations into the new feature stores from PRs 04-07 rather than mutating everything inside one type.
- Add tests around reconnect and event application ordering.

Acceptance criteria:

- Live sync still reconnects after stream termination and heartbeat timeout.
- Diagnostics still reflect the live sync status and last error.
- Event ordering/idempotency remains stable for sessions, transcript updates, permissions, and questions.

## PR 09 - Split Transcript UI Into Feature Files

Goal: make transcript rendering navigable and locally understandable.

Scope:

- Move transcript UI into a feature folder such as `kodanto/Features/Transcript/`.
- Split `kodanto/Views/TranscriptTurnView.swift` into:
  - transcript turn shell
  - user turn view
  - assistant turn view
  - per-tool cards
  - shared blocks/components
- Replace loose disclosure dictionaries with a typed disclosure store or typed keys.
- Move view-only formatting into presentation helpers where it clarifies the code.

Acceptance criteria:

- Transcript rendering is visually unchanged.
- Tool cards still show shell output, patch details, diagnostics, question answers, and task navigation.
- The main transcript files become small enough to scan quickly.

## PR 10 - Split Main Shell UI Into Feature Files

Goal: make the app shell mostly composition and routing instead of a 1900-line controller view.

Scope:

- Move `kodanto/Views/MainView.swift` into feature folders such as:
  - `Features/MainShell/`
  - `Features/Connections/`
  - `Features/SessionDocks/`
- Extract focused views for:
  - sidebar
  - session detail pane
  - prompt composer
  - connection status popover
  - diagnostics sheet
  - connections manager
- Move shell-specific local state into focused controllers where appropriate:
  - expanded project IDs
  - drag/drop target state
  - sidebar focus state
  - transcript scroll/disclosure coordination

Acceptance criteria:

- `MainView` becomes a thin shell that wires together feature views.
- Keyboard navigation, drag/drop reordering, sheets, and popovers still behave the same.
- The extracted files map to features instead of random visual fragments.

## PR 11 - Optional Module Split Into Local Packages

Goal: create stronger compile-time boundaries once the feature and service seams are proven.

Scope:

- Extract stable non-UI layers into local Swift packages or framework targets, for example:
  - `KodantoCore`
  - `KodantoServices`
  - `KodantoPresentation`
- Keep SwiftUI app-specific composition in the app target.
- Move tests alongside the extracted modules where that improves feedback speed.

Acceptance criteria:

- The app still builds cleanly against the package/module boundaries.
- Cross-module dependencies are one-directional and reflect the new architecture.
- This PR is skipped if the earlier refactors already produce acceptable maintainability without modularization.

## Suggested File Layout After PR 10

```text
kodanto/
  App/
  Core/
    Persistence/
    Ordering/
    Support/
  Features/
    Connections/
    MainShell/
    SessionDocks/
    Transcript/
    Workspace/
  Presentation/
  Services/
  Models/
```

## Recommended Stopping Points

- After PR 03: the codebase becomes meaningfully more testable.
- After PR 06: transcript and session detail logic is finally isolated.
- After PR 08: the main architecture risk is mostly addressed.
- After PR 10: the day-to-day maintainability problem should be substantially improved even if PR 11 never happens.
