# Clarity GitHub Release Runbook

Use this runbook to publish a signed and notarized Clarity ZIP through GitHub
Releases. The production workflow is `.github/workflows/release.yml` and runs
when a tag matching `v*` is pushed.

## Know which artifact you are using

Pull requests and pushes to `main` run CI and upload a `Clarity-macos` workflow
artifact. That ZIP is ad-hoc signed and is suitable only for internal testing.
It is not notarized and must not be presented as a public release.

A public GitHub Release is built by the **Release** workflow. It is signed with
a Developer ID Application certificate, notarized by Apple, stapled, checked
with Gatekeeper, and then attached to the GitHub Release as
`Clarity-vX.Y.Z.zip`.

## One-time setup

### 1. Prepare Apple credentials

You need:

- An active Apple Developer Program membership.
- A Developer ID Application certificate and its private key in Keychain
  Access.
- An Apple ID that can notarize for the developer team.
- An app-specific password generated for that Apple ID.
- The Apple Developer Team ID.

Confirm the available signing identity:

```sh
security find-identity -p codesigning -v
```

Use the full `Developer ID Application: ...` value for
`APPLE_SIGNING_IDENTITY`. Do not use an `Apple Development` or `Mac Developer`
identity.

In Keychain Access, select the Developer ID Application certificate and its
private key, export them together as a password-protected `.p12`, and keep the
file outside the repository. Copy its base64 representation with:

```sh
base64 < /path/to/developer-id-application.p12 | pbcopy
```

Do not commit the certificate, its password, or any Apple credentials.

### 2. Configure GitHub Actions secrets

Open the repository on GitHub, then go to **Settings → Secrets and variables →
Actions → New repository secret**. Add all seven secrets:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 text copied from the exported `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID Application identity |
| `APPLE_KEYCHAIN_PASSWORD` | New random password used only for the temporary CI keychain |
| `APPLE_ID` | Apple ID permitted to notarize the app |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

The workflow stops before building if any secret is absent.

If using the GitHub CLI, confirm it is authenticated first:

```sh
gh auth status
gh auth login
```

GitHub never reveals stored secret values. Confirm only that all seven names
exist:

```sh
gh secret list --repo markpinero/clarity
```

## Publish a release

Replace `v0.1.0` below with the intended semantic version.

### 1. Prepare `main`

Start from a clean checkout whose `main` branch matches GitHub:

```sh
git switch main
git pull --ff-only
git status --short --branch
```

Review the release commit and recent changes:

```sh
git log -1 --oneline
git log --oneline --no-merges $(git describe --tags --abbrev=0 2>/dev/null)..HEAD
```

If this is the first tag, the second command will show no range. Review the
history directly instead.

### 2. Verify locally

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
CLARITY_RELEASE_VERSION=0.1.0 ./script/build_and_run.sh --release
codesign --verify --deep --strict dist/release/Clarity.app
test -s dist/release/Clarity.zip
```

The local archive is ad-hoc signed unless `CLARITY_CODESIGN_IDENTITY` is
supplied. This local check verifies compilation and bundle construction; it
does not replace the signed and notarized GitHub workflow.

Also confirm the latest `main` CI run is green in GitHub Actions. With an
authenticated GitHub CLI:

```sh
gh run list --repo markpinero/clarity --workflow CI --branch main --limit 5
```

### 3. Create and push the version tag

Fetch tags and confirm the intended tag does not already exist:

```sh
git fetch --tags
git tag --list v0.1.0
```

An empty result means the tag is available. Tag the exact release commit and
push only that tag:

```sh
git tag -a v0.1.0 -m "Clarity v0.1.0"
git push origin v0.1.0
```

Pushing the tag triggers the **Release** workflow. The workflow:

1. Validates the seven required secrets.
2. Imports the Developer ID certificate into a temporary keychain.
3. Runs `swift test`.
4. Builds with hardened runtime and a secure timestamp.
5. Submits the ZIP to Apple notarization and waits for a result.
6. Staples the notarization ticket and verifies Gatekeeper acceptance.
7. Creates the GitHub Release with generated notes and the notarized ZIP.

### 4. Monitor the workflow

Open the **Release** workflow in GitHub Actions, or use:

```sh
gh run list --repo markpinero/clarity --workflow Release --limit 5
gh run watch RUN_ID --repo markpinero/clarity --exit-status
```

Do not announce the release until every step has passed and the ZIP appears on
the GitHub Release page.

### 5. Smoke-test the published asset

Download `Clarity-v0.1.0.zip` from the GitHub Release and test it on a Mac that
has not run a local Clarity development build. After extracting the ZIP, check
the published app:

```sh
codesign --verify --deep --strict --verbose=2 /path/to/Clarity.app
spctl --assess --type execute --verbose=4 /path/to/Clarity.app
xcrun stapler validate /path/to/Clarity.app
```

Then launch the downloaded app and verify at minimum:

- Gatekeeper does not report an unidentified or damaged application.
- The menu-bar item appears and the main Clarity window opens.
- Display controls and break scheduling load normally.
- The version in `Clarity.app/Contents/Info.plist` matches the release tag
  without the leading `v`.

## Failure recovery

### Missing secret

Add the named repository secret and rerun the failed workflow from GitHub
Actions. Do not print secret values into workflow logs.

### Certificate import or signing failure

Confirm that the `.p12` contains both the Developer ID Application certificate
and its private key, the export password is correct, and
`APPLE_SIGNING_IDENTITY` exactly matches `security find-identity`.

### Notarization failure

Open the failed `notarytool` step and inspect Apple's rejection message. Common
causes are invalid notarization credentials, a mismatched Team ID, missing
hardened runtime, or an invalid nested signature. Fix the cause before creating
another release.

### Bad version or bad release commit

Do not move or overwrite a published version tag. Fix the problem on `main` and
publish a new patch version, such as `v0.1.1`. Delete and recreate a tag only if
the workflow failed before publication and nobody could have consumed it.

## Release checklist

- [ ] Intended changes are merged to `main`.
- [ ] Working tree and release commit were reviewed.
- [ ] Local `swift test` passed.
- [ ] Local release bundle was constructed and verified.
- [ ] Latest `main` CI run is green.
- [ ] All seven GitHub Actions secrets exist.
- [ ] Version tag is new and points to the intended commit.
- [ ] Release workflow completed successfully.
- [ ] GitHub Release contains the notarized ZIP.
- [ ] Published ZIP passed signature, Gatekeeper, staple, and smoke tests on a
      clean Mac.
