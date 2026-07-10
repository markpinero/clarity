# Releasing Clarity

## CI artifacts

Pull requests and pushes to `main` run the Swift suite and create an ad-hoc signed release ZIP. Download the `Clarity-macos` workflow artifact for tester-only builds. It is not notarized and must not be presented as a public release.

Run the equivalent local build with:

```sh
./script/build_and_run.sh --release
```

This writes `dist/release/Clarity.app` and `dist/release/Clarity.zip`. Supply `CLARITY_CODESIGN_IDENTITY` to sign locally with a Developer ID identity; otherwise the local build is ad-hoc signed.

## GitHub Release setup

Before creating the first `v*` tag, add these repository Actions secrets:

- `APPLE_CERTIFICATE_P12_BASE64`: base64-encoded Developer ID Application `.p12` certificate.
- `APPLE_CERTIFICATE_PASSWORD`: password for that `.p12` file.
- `APPLE_SIGNING_IDENTITY`: the full Developer ID Application identity shown by `security find-identity -p codesigning -v`.
- `APPLE_KEYCHAIN_PASSWORD`: a randomly generated CI-only keychain password.
- `APPLE_ID`: Apple ID permitted to notarize the app.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for that Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.

The release workflow fails before building if any secret is absent. It imports the certificate into a temporary keychain, builds with hardened runtime and a timestamp, submits the ZIP to Apple notarization, staples the resulting ticket, verifies Gatekeeper assessment, and attaches `Clarity-vX.Y.Z.zip` to the GitHub Release.

## Publishing

1. Ensure `main` is green.
2. Create and push a version tag such as `v0.1.0`.
3. Wait for the **Release** workflow to finish.
4. Download the GitHub Release asset and smoke-test it on a Mac that has not run a local Clarity build.

The current local bundle is ad-hoc signed and has no Developer ID identity installed. The GitHub release workflow is therefore the production signing path once the required secrets are configured.
