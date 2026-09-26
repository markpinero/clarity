# Clarity

Clarity is a native macOS menu-bar app for adaptive display temperature, brightness, and screen-break reminders. It includes solar-aware Health scheduling, per-display controls, configurable focus breaks, and context-aware pause handling.

## Requirements

- Runtime: macOS 13 Ventura or later
- Development: Xcode 26 or a compatible full Xcode toolchain on a supported macOS host

## Run

```sh
./script/build_and_run.sh
```

Clarity starts with display adjustments off. Configure and enable it from the control window or menu bar.

## Development rebuilds

Use the build script as the normal development entry point:

```sh
./script/build_and_run.sh
```

It quits the running Clarity process, builds the debug executable, recreates the
fresh `dist/Clarity.app` bundle, signs it with the local Apple Development
identity, and launches it. Development builds fail if that identity is missing;
`CLARITY_CODESIGN_IDENTITY` can select a different Apple Development identity.

```sh
# Run the test suite, then rebuild and launch.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  && ./script/build_and_run.sh

# Rebuild the application bundle without launching it.
./script/build_and_run.sh --stage

# Create a local release archive in dist/release/.
CLARITY_RELEASE_VERSION=0.1.1 ./script/build_and_run.sh --release
```

Do not use `open -a Clarity` or launch the installed copy from Applications while
developing: either may start an older build. Launch through the script instead.
When the staged development bundle asks to move itself to Applications, choose
**Not Now** unless replacing the installed copy is intentional.
