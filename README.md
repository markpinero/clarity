# Clarity

Clarity is a native macOS menu-bar app for adaptive display temperature, brightness, and screen-break reminders. It includes solar-aware Health scheduling, per-display controls, configurable focus breaks, and context-aware pause handling.

## Requirements

- macOS 14 or later
- Xcode 26 or a compatible full Xcode toolchain

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
fresh `dist/Clarity.app` bundle, ad-hoc signs it, and launches it.

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
**Not Now** so it does not replace the installed copy with an ad-hoc build.
