# AGENTS.md

## Project overview

Clarity is a native macOS 14+ menu-bar app built with Swift 6 and Swift Package Manager. It controls display temperature and brightness, schedules profiles, and provides configurable screen-break reminders.

## Environment

- Use macOS 14 or later.
- Use Xcode 26 or a compatible full Xcode installation.
- Run all commands from the repository root.
- Select the full Xcode toolchain before building, testing, or packaging:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```

## Initialize

Initialize a fresh checkout with:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift package resolve
```

The project has no third-party package dependencies and requires no additional bootstrap or install step.

## Commands

| Task | Command |
| --- | --- |
| Build | `swift build` |
| Run all tests | `swift test` |
| Run focused tests | `swift test --filter TestCaseName` |
| Build and launch development app | `./script/build_and_run.sh` |
| Stage signed development bundle | `./script/build_and_run.sh --stage` |
| Build local release archive | `CLARITY_RELEASE_VERSION=<version> ./script/build_and_run.sh --release` |

The commands above assume `DEVELOPER_DIR` was exported during initialization. If the shell is new, export it again first.

## Source layout

- `Sources/ClarityCore`: display adjustment, scheduling, preferences, and shared application services.
- `Sources/ClarityBreaks`: break configuration, state, persistence, and reducer logic.
- `Sources/ClarityDiagnostics`: executable app, AppKit integration, controllers, and SwiftUI views.
- `Tests/ClarityCoreTests`: tests for `ClarityCore`.
- `Tests/ClarityBreaksTests`: tests for `ClarityBreaks`.
- `Tests/ClarityDiagnosticsTests`: tests for executable-layer behavior.

Keep meaningful domain and state logic in the library targets when possible. Keep AppKit and SwiftUI concerns in `ClarityDiagnostics`.

## Implementation guidelines

- Keep changes narrowly scoped to the requested behavior.
- Preserve unrelated working-tree changes.
- Match the existing Swift 6 style and two-space indentation.
- Format only files in scope with `swift format format --in-place <files>`.
- Add tests for meaningful state, reducer, persistence, or policy behavior.
- Place tests in the target corresponding to the code under test.
- Avoid unrelated refactors and repository-wide mechanical formatting.

## Verification

- Run the most focused relevant tests while iterating.
- Run `swift test` before handing off a completed code change.
- Use `./script/build_and_run.sh --stage` when bundle construction or metadata is affected.
- Report exactly what was verified and what was not.
- Two display integration tests are skipped by default. They run only with `CLARITY_RUN_HARDWARE_TESTS=1` and modify the current displays; do not enable them without explicit intent.
- For UI changes, verify the rendered app when practical and report if verification was limited to build or accessibility inspection.

## Development app safety

- Prefer `./script/build_and_run.sh --stage` for non-interactive bundle verification.
- Use `./script/build_and_run.sh` only when launching the app is part of the task.
- Do not launch with `open -a Clarity`; macOS may select an older installed copy.
- If a development build offers to move itself into Applications, choose **Not Now** unless installation is explicitly part of the task.

## Git workflow

- Stage files by exact path. Never sweep unrelated worktree changes into a commit.
- Keep commits atomic: one coherent change plus its directly related tests or documentation.
- Use Conventional Commits, such as `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `build:`, or `chore:`. Add a scope when it improves clarity.
- Write commit subjects in imperative mood.
- Do not add AI attribution or co-author trailers.
