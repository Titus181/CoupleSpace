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
4. Read the relevant product scope, roadmap, tests, and Evals before changing behavior.
5. Read the nearest nested `AGENTS.md` if one is added later.

## Commands

Run from the repository root. Use RTK-wrapped shell commands by default.

- Environment check: `rtk xcodebuild -version`
- Project inventory: `rtk xcodebuild -list -project CoupleSpace.xcodeproj`
- iPhone build: `rtk xcodebuild build -project CoupleSpace.xcodeproj -scheme CoupleSpace -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- iPhone tests: `rtk xcodebuild test -project CoupleSpace.xcodeproj -scheme CoupleSpace -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`
- Watch tests, only when Watch behavior or shared code changes: `rtk xcodebuild test -project CoupleSpace.xcodeproj -scheme 'CoupleSpace Watch App Watch App' -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest'`
- Diff hygiene: `rtk git diff --check`
- Harness integrity: `rtk ../../agent-harness/scripts/project-harness.sh check .`

There is no standalone linter configured yet. Do not claim lint passed; the Swift compiler build and
`git diff --check` are the current automated static gates.

## Project Boundaries

- iPhone is the MVP development and verification priority. Watch, macOS, visionOS, Widget, StoreKit, and AI features must not delay the iPhone core loop.
- Keep product-specific architecture, permissions, Skills, tests, and Evals in this repository.
- Do not edit vendored files under `.harness/shared/` or the shared Skill files directly.
- Prefer Xcode-managed project changes. If `project.pbxproj` must change, keep the diff minimal and verify target membership and both Debug and test builds.
- Never commit API keys, CloudKit credentials, signing material, device identifiers, private messages, photos, notification payloads, or production exports.
- External writes, deployments, TestFlight uploads, CloudKit schema promotion, destructive data operations, and notifications to real users require explicit human authorization.
- Analytics must not contain private message text, photo content, or other unnecessary intimate data.

## Testing Policy

- Every behavior change needs a test at the lowest reliable layer. A bug fix must add a regression case that fails before the fix when practical.
- Do not mechanically duplicate every feature across unit, integration, and UI tests. Use unit tests for deterministic rules, integration tests for storage/sync/service boundaries, UI tests for critical journeys, and real-device tests for Apple services and cross-device behavior.
- During development, run affected tests and the affected target build.
- Work in the smallest complete vertical slice and finish all locally automatable implementation, affected tests, Simulator builds, and Harness checks before requesting human validation; do not interrupt the user to manually test each incremental edit.
- Batch human validation at a coherent slice or milestone boundary, with one concise checklist. Request it earlier only when progress requires Xcode UI, Apple ID, signing, a real device, push/background behavior, cross-device Apple-service behavior, destructive remote-test-data approval, or subjective UX judgment.
- Before a PR is merged, run the full iPhone automated suite plus applicable integration/UI tests. Run Watch tests only when Watch or shared behavior is affected.
- Before TestFlight or release, execute the two-iPhone/two-Apple-ID, weak-network, offline, push privacy, App Lock, export, deletion, and unpairing checks in `docs/HARNESS.md`.
- A fresh green result is required after the final code change. Do not reuse a test result from before the last behavior-affecting edit.
- Flaky tests are defects. Do not hide them with unconditional retries or silently weaken assertions.

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
