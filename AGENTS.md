# AGENTS.md

Oto is a Swift 6 / SwiftUI music app for iOS and iPadOS. Build for the owner's devices first, with possible small-group sharing later. App Store work is outside the current scope. The owner confirmed a minimum OS of iOS/iPadOS 17 with visual fallbacks; the primary physical test devices are iPad (9th generation) and iPhone 13 Pro Max. Do not depend on ProMotion or newer visual APIs for core features.

## Current state and relevant documents

The repository currently contains planning documents, not a working app or verified playback backend. Do not invent successful builds, existing schemes, installed skills, or device results.

- Read `PROJECT_PLAN.md` for scope and architecture changes.
- Use `docs/PRODUCT_INPUTS.md` for owner decisions and unresolved preferences; proposed defaults are not confirmed requirements.
- Use `docs/AGENT_WORKFLOW.md` for Gemini implementation and Codex review handoffs.
- Use `docs/CLI_CONNECTION.md` for the verified Antigravity (`agy`) and Codex command interfaces. The owner's Gemini implementer runs through Antigravity CLI, not the separate `gemini` executable.
- Use `docs/RUNNER_GUIDE.md` and `runner/backlog.json` for automated task execution. A task must be explicitly marked `READY`; merely adding it does not authorize missing approvals such as UI tests, physical-device runs, dependencies, or account mutations.
- Use `design/references/README.md` when collecting or interpreting visual references.
- Use `docs/PLAYBACK_FEASIBILITY.md` for playback, auth, lifecycle, or background changes.
- Use `docs/KASET_PORTING_AUDIT.md` when reusing Kaset code.
- Record significant architecture decisions in `docs/adr/`; distinguish proposed choices from measured conclusions.

## Working style and authorization

- Complete the requested scope, make routine implementation decisions, and ask only when a choice materially changes the product or needs missing information.
- Preserve unrelated user changes. Do not modify the Kaset checkout as part of an Oto task unless requested.
- Gemini through Antigravity CLI (`agy`) is the primary implementer; Codex is the reviewer. During a review, Codex reports findings and does not edit product code unless the owner explicitly changes the assignment. Reviewer-authored reports are permitted.
- Before automated Git writes, verify that the Git root is Oto, not a parent directory containing sibling projects. Restrict every task and diff to its intended scope.
- The owner requires a task-scoped commit and push after each coding task has passed its required checks and Codex review, to `https://github.com/TuiLaHieu1/Oto---Youtube-Music-Player`. This is standing authorization for that completion workflow; do not ask again for each task. Verify the isolated repository, remote and branch first. Never force-push or include unrelated work. A failed push leaves the task delivery incomplete and must be reported, not bypassed.
- Write necessary explanatory code comments, commit messages, review findings and user handoffs in simple Vietnamese. Keep code identifiers and API names idiomatic; do not add redundant comments to every declaration.
- Use Gemini's existing Google Login/Pro allowance and Codex's existing ChatGPT login allowance, as confirmed by the owner. Do not switch to metered API/Vertex credentials, paid fallback models, or purchased capacity. Stop when the existing allowance is exhausted.
- Autonomous overnight sessions must stop by 05:00 in `Asia/Ho_Chi_Minh`. Before starting a loop, record its exact dated cutoff (the next 05:00 unless the owner specifies a date). Do not auto-start a new session after that cutoff. Before ending for any reason, save a Vietnamese handoff with task/revision/check results, pushed versus local work, blockers, and the next step; see `docs/AGENT_WORKFLOW.md`.
- Ask before adding a third-party dependency, launching UI tests, installing/running on a physical device, or sending exploratory requests that mutate a real account. Existing explicit session authorization counts; do not ask repeatedly.
- Build/unit checks may run autonomously. User-facing actions in the finished app are distinct from agent-run live account probes.
- Do not publish, push, upload builds, change developer-account settings, or access personal session archives without task authorization.
- Report what changed, which checks actually ran, unresolved blockers, and the next concrete step. Documentation work does not require pretending to run nonexistent app tests.

## Security and session handling

- Never expose real cookies, SAPISID, tokens, API keys, passwords, account emails, signing secrets, or raw authenticated payloads in code, logs, fixtures, docs, commits, or responses. Use `REDACTED`, `mock-token`, or `test-cookie`.
- Never read/export the owner's Google session from Kaset merely because it exists. Each Oto installation authenticates separately.
- Use native Security.framework Keychain for secrets; never UserDefaults or ordinary cache files. Keep session material out of UI state and default debug descriptions.
- Sign-out cancels requests, fences stale callbacks, clears account caches and credential backups, and prevents observers from restoring deleted credentials.
- Do not assume browser OAuth yields WebKit cookies. Verify the chosen sign-in/session integration; do not bypass Google sign-in restrictions or ask the user to paste credentials into chat.
- Scope bridge/navigation handlers to expected origins, validate message shape/session/track identity, and unregister handlers on teardown. Never interpolate untrusted track text into JavaScript source; use structured arguments or safe serialization.

## Architecture and coding rules

- Swift language mode 6 with strict concurrency. Mark observable application/UI reference stores `@MainActor`; use actors for isolated mutable service state where appropriate.
- Keep shared domain/queue/lyrics logic free of AppKit and platform playback/session ownership. Use dependency injection for transport, session provider, playback backend, clock, and storage.
- Use SwiftUI, Observation, async/await, structured cancellation, `NavigationStack`/`NavigationSplitView`, and `.task` for view-bound asynchronous work.
- A shared playback coordinator owns one active session across scenes; views observe it. Do not create a player per sheet or require a global singleton.
- No force unwraps, `try!`, `unsafeBitCast`, or `@unchecked Sendable` as shortcuts. Use explicit `self` in instance members and `Self` in static calls, matching the selected formatter.
- Keep parser-required IDs/containers validated. Optional/default everything is not graceful degradation: distinguish schema mismatch from empty results.
- Playback intent, engine state, queue identity, and request generation are separate. Ignore stale load/seek/lyrics results; advance a queue item at most once.
- No silent audio keepalive, private API, fake background assertions, DRM bypass, ad blocking, or hidden tiny-video workarounds.
- Treat WKWebView as a candidate backend until device evidence supports it. Audio-session flags and a passing macOS implementation do not establish iOS background compatibility.
- Activate the audio session when playback requires it, and handle interruption/route changes according to user intent. Do not interrupt other audio at app launch.

## API and lyrics work

- Prefer verified API requests for catalog data; WebKit is limited to the selected session/playback integration. Innertube is undocumented: isolate its adapter and expose errors clearly.
- Before changing an endpoint, request shape, or response parser, verify real behavior through a reusable API explorer. Extend the explorer rather than adding one-off authenticated scripts. No live probes are needed for a docs-only plan.
- Keep raw captures outside the repo and out of tool output; sanitize credentials and personal metadata before creating fixtures. Never use network/account access in unit tests.
- Handle auth expiry, rate limits, cancellation, and transport failure separately; use bounded retries and honor Retry-After. Determine 401/403 semantics from the specific endpoint; do not hide permission/content errors as generic auth expiry.
- Reuse Kaset lyrics/provider/LRC ideas where suitable. LRCLIB and verified YTM are initial candidates; other providers need appropriate access/usage rights before implementation.
- Preserve recording identity (live/remix/remaster), raw metadata, instrumental state, provider attribution, and actual timing precision. Do not manufacture word timing from plain/line lyrics.

## UI, performance, and localization

- Design for compact windows, phone landscape, iPad multitasking and resizing; use size/layout constraints rather than only device idiom.
- Support VoiceOver, Dynamic Type, Reduce Motion, light/dark mode, and reliable 60 Hz interaction. Animate only visible surfaces; use static backgrounds when needed.
- Gate newer APIs with availability checks and usable fallbacks. No Metal/ActivityKit requirement in MVP.
- Use the app's String Catalog for Vietnamese/English. Do not copy Kaset's macOS SwiftPM localization-mirror rules unless the new build actually needs mirrors.
- Keep caches bounded and account scoped. Never label an in-memory queue/library cache as an authoritative server mutation.

## Measurement and verification

For lifecycle/timing/background bugs: add a sanitized timestamped trace, reproduce on the appropriate device, fix what the measurement shows, re-measure, and remove throwaway traces. Simulator playback or a native test asset is not proof that YTM plays in the background.

New unit tests use Swift Testing (`@Test`, `#expect`). Focus on queue transitions, duplicate completion events, stale async responses, parser contracts, lyric matching, clock behavior, and session isolation. Use synthetic or sanitized fixtures and injected clocks/transports.

There is no Xcode project, scheme, formatter config, or build script yet. In foundation, establish and verify commands before documenting them as runnable:

1. Record `xcodebuild -version`, `swift --version`, actual project/schemes, and installed simulator destinations.
2. Add a shared app scheme and a test plan containing only unit tests for routine checks. Keep UI tests separately selectable and approval-gated.
3. Verify simulator build and unit-test commands with an installed destination, plus unsigned generic-device compile when applicable.
4. Pin SwiftLint/SwiftFormat versions and configure checks for touched code; do not reformat unrelated files.
5. Run the physical matrix for playback/lifecycle changes with device-run authorization; mark unavailable rows NOT TESTED, never PASS.

After non-trivial code changes and focused checks, use independent autoreview when the workflow is available. Review the correct diff/commit scope and validate findings against actual paths. Do not commit solely to make review tooling work, or claim a missing helper was run. Docs-only changes may skip code review/builds. If the owner requests a commit/push workflow, run final review before pushing and report accepted/rejected findings with reasons.

## Agent skills

Repo-local skills belong under `.agents/skills/<name>/SKILL.md` with accurate name/description metadata. Proposed skills are listed in `PROJECT_PLAN.md`; they are not installed merely because that list exists. Read a skill before applying it. Create workflows from tested steps, and never copy Kaset's macOS paths/signing/cookie assumptions into iOS instructions.

Keep AGENTS focused on stable project rules; put long product requirements, device evidence, and detailed workflows in their own documents.
