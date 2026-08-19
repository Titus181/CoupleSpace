# CoupleSpace Project Guidance

## Purpose

CoupleSpace 是以 iPhone 為首要平台的一對一伴侶私人空間。首版核心循環是：

`配對 → Moment／共同約定 → 雙向互動／約定討論 → 對話 → 收藏 → 共同時間線`

目前產品範圍與完成條件以 `docs/product/04-iphone-mvp-scope.md` 及
`docs/operations/01-v1-development-roadmap.md` 為準。尚未完成 G1 技術驗證的方案，不得寫成既定架構。

## Read Order

1. Read this file.
2. Read `harness-version.yaml` and `docs/HARNESS.md`.
3. Read `docs/ARCHITECTURE.md`.
4. Read `quality/README.md`, the relevant test catalog entries, product scope, roadmap, tests, and Evals before changing behavior.
5. Read the nearest nested `AGENTS.md` if one is added later.

## Commands

Run from the repository root. Use RTK-wrapped shell commands by default.

- Environment check: `rtk xcodebuild -version`
- Project inventory: `rtk xcodebuild -list -project CoupleSpace.xcodeproj`
- iPhone build: `rtk xcodebuild build -project CoupleSpace.xcodeproj -scheme CoupleSpace -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- iPhone tests: `rtk xcodebuild test -project CoupleSpace.xcodeproj -scheme CoupleSpace -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`
- Watch tests, only when Watch behavior or shared code changes: `rtk xcodebuild test -project CoupleSpace.xcodeproj -scheme 'CoupleSpace Watch App Watch App' -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest'`
- Full local automated gates: `quality/scripts/run-full-automated-suite.sh`
- TestFlight/release-candidate automated gates: `quality/scripts/run-full-automated-suite.sh --reset-local-database`
- Diff hygiene: `rtk git diff --check`
- Harness integrity: `rtk ../../agent-harness/scripts/project-harness.sh check .`

There is no standalone linter configured yet. Do not claim lint passed; the Swift compiler build and
`git diff --check` are the current automated static gates.

## Project Boundaries

- iPhone is the MVP development and verification priority. Watch, macOS, visionOS, Widget, StoreKit, and AI features must not delay the iPhone core loop.
- Android is a post-launch expansion candidate, not current implementation scope. Do not create an Android client, choose a cross-platform UI stack, add a second auth provider, or build speculative adapters before an accepted Android roadmap.
- When the current iPhone slice already requires a Domain or remote contract, keep relationship membership, invitations, content identity, idempotency, sync state, data lifecycle, and entitlements platform-neutral when doing so does not add scope or complexity. Never use Apple ID, bundle identifiers, APNs tokens, or StoreKit transactions as shared product-data identity.
- Keep Apple-only authentication, push, deep links, App Lock, purchases, background execution, and UI behavior behind Data／Platform boundaries. A future Android adapter must be able to use the same Supabase user／relationship contracts, but do not introduce protocols solely for a hypothetical second implementation.
- Preserve stable Supabase user UUIDs across any future auth-provider expansion. Adding Google, LINE, Email, or another login requires an accepted identity-linking and recovery plan before implementation so an existing relationship or personal archive cannot appear lost.
- Keep product-specific architecture, permissions, Skills, tests, and Evals in this repository.
- Do not edit vendored files under `.harness/shared/` or the shared Skill files directly.
- Prefer Xcode-managed project changes. If `project.pbxproj` must change, keep the diff minimal and verify target membership and both Debug and test builds.
- Never commit API keys, CloudKit credentials, signing material, device identifiers, private messages, photos, notification payloads, or production exports.
- Treat account credentials supplied out of band as ephemeral local testing secrets. Never copy them into repository files, docs, fixtures, scripts, shell commands or history, logs, screenshots, release records, commits, or uploads, and never echo them in reports. Prefer reusing an already-authenticated Simulator; if credential entry is unavoidable, enter it only through the local interactive UI.
- External writes, deployments, TestFlight uploads, CloudKit schema promotion, destructive data operations, and notifications to real users require explicit human authorization.
- Analytics must not contain private message text, photo content, or other unnecessary intimate data.

## Testing Policy

- Simulator-first is the default. Use deterministic unit／integration／UI tests and the available isolated iPhone Simulators for every behavior they can faithfully exercise, especially failure, timeout, concurrency, restart, multi-client, same-account, two-account, unread／badge, Outbox, and lifecycle edge cases.
- Prefer controlled fault injection and repeatable Simulator fixtures over asking the user to reproduce edge conditions manually on a physical iPhone. Reuse already-authenticated Simulator fixtures when safe, but verify the current device／account roles at runtime instead of hard-coding transient topology or treating a device name as Auth identity.
- Do not request or operate a physical iPhone while equivalent evidence is obtainable in Simulator. Reserve real-device work for irreducible hardware／Apple-service or explicit release gates, such as actual APNs delivery, hardware biometric／passcode and lock-screen privacy, TestFlight installation／upgrade, or a contract that specifically requires physical-device evidence. Batch those unavoidable checks into one concise final checklist.
- Every behavior change needs a test at the lowest reliable layer. A bug fix must add a regression case that fails before the fix when practical.
- Do not mechanically duplicate every feature across unit, integration, and UI tests. Use unit tests for deterministic rules, integration tests for storage/sync/service boundaries, UI tests for critical journeys, and real-device tests for Apple services and cross-device behavior.
- During development, run affected tests and the affected target build.
- Work in the smallest complete vertical slice and finish all locally automatable implementation, affected tests, Simulator builds, and Harness checks before requesting human validation; do not interrupt the user to manually test each incremental edit.
- Batch human validation at a coherent slice or milestone boundary, with one concise checklist. Request it earlier only when progress requires Xcode UI, Apple ID, signing, a real device, push/background behavior, cross-device Apple-service behavior, destructive remote-test-data approval, or subjective UX judgment.
- Before a PR is merged, run the full iPhone automated suite plus applicable integration/UI tests. Run Watch tests only when Watch or shared behavior is affected.
- Before TestFlight or release, execute the two-iPhone/two-Apple-ID, weak-network, offline, push privacy, App Lock, export, deletion, and unpairing checks in `docs/HARNESS.md`.
- `quality/test-catalog.md` is the canonical test index and `quality/release-gates.md` defines the blocking evidence required for TestFlight and public releases. Record every release candidate with `quality/release-record-template.md`.
- A fresh green result is required after the final code change. Do not reuse a test result from before the last behavior-affecting edit.
- Flaky tests are defects. Do not hide them with unconditional retries or silently weaken assertions.

## Complete Test Workflow

- When the user asks for `完整測試` or says `閱讀 quality/ 內的文件，依 Gate C 執行完整測試`, treat it as authorization to run the complete local test workflow, but not to deploy, commit, or push.
- First read `quality/README.md`, `quality/test-catalog.md`, `quality/release-gates.md`, the applicable `quality/manual/` checklists, and the release-record template. For W8–W11 behavior, also read `quality/manual/w8-w11-regression.md`.
- Verify that the reset target is the local disposable Supabase test database, then run Gate C's locally automatable checks: unit tests, database／integration tests, UI tests, schema lint, Edge Function tests, the full iPhone scheme, applicable Watch tests, Agent Evals, Harness, and diff hygiene. Record runtime executions, failures, skips, exit status, commit, build, and environment; a build-only result is not a test pass.
- After the ordinary automated suite is green, run an applicable multi-iPhone-Simulator preflight before asking for physical-device work. Use the available isolated Simulator devices and test identities／fixtures to exercise cross-client sync, Realtime, unread state, Outbox／FIFO, restart recovery, deduplication, source navigation, shared-appointment flows, same-account isolation, and deterministic boundary cases. Record unavailable identity or fixture seams as `BLOCKED`; do not silently skip them.
- Simulator results are the primary development evidence and may close behavior that the Simulator faithfully exercises. They cannot replace an explicitly required physical-device gate for actual APNs, hardware biometric／passcode and lock-screen behavior, TestFlight upgrade, low-storage, or another irreducible device condition.
- Only after all locally automatable and Simulator checks finish, provide one consolidated checklist limited to the remaining irreducible physical-device validation. Do not ask the user to repeat Simulator-covered edge cases manually unless the release SSOT explicitly requires the physical-device version. Do not deploy, commit, push, alter linked／production data, or claim Gate C complete without separate authorization and any still-required fresh physical-device evidence.

## Stop Conditions

Stop feature work and address the failure first if a change can cause data to be sent to the wrong person,
private notification leakage, message loss/duplication/reordering, inconsistent deletion or unpairing, or an authorization boundary violation.

## Shared and Local Harness

- Shared assets in `.agents/skills/` and `.harness/shared/` are vendored from the release recorded in `harness-version.yaml`.
- Never load shared behavior from `agent-harness/main` at runtime.
- Shared changes require a SemVer release and a reviewed project upgrade diff. CoupleSpace-only rules remain local.
- Project rules may tighten shared rules but must not silently weaken security constraints.

## Git Handoff

- At the end of every task, assess whether the validated changes form a coherent commit and whether pushing is appropriate.
- When the timing is appropriate, remind the user and state the recommended commit or push scope. A reminder is not authorization: do not commit or push unless the user explicitly requests it.

## Completion Criteria

- The requested behavior and acceptance criteria are satisfied.
- Affected tests pass, and the required regression test was added or updated.
- The affected target builds; PR/release gates are completed at the appropriate stage.
- Applicable Agent Evals pass.
- Documentation matches changed behavior and unresolved facts remain explicitly undecided.
- `project-harness.sh check` and `git diff --check` pass.
- The final diff contains no unrelated changes.
