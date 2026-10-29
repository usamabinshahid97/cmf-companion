# Distributing CMF Companion

The app source and releases are hosted at <https://github.com/usamabinshahid97/cmf-companion>. The cask lives in <https://github.com/usamabinshahid97/homebrew-tap>.

The current public binary is version **1.1.5**, build **9**, for **arm64 / macOS 14+**. It uses an ad hoc signature. It is not Developer ID signed or Apple notarized. Users may need Apple's per-app **Open Anyway** flow on first launch. The cask preserves Homebrew's normal quarantine behavior and never changes Gatekeeper settings.

## Prepare a new release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Never replace an existing published version's binary with different bytes.
2. Run `swift test`, build the app, and complete the live checks appropriate to the changes. Record known verification limits in the release notes.
3. Run `bash scripts/package-release.sh`. It builds the app, verifies the signature, packages the bundle with `ditto`, checks ZIP integrity, and writes its SHA-256 file. The script can package an already-built, verified bundle with `--skip-build`.
4. Review and commit only the app's source, resources, tests, build scripts, public documentation, and licenses. Keep local diagnostics, evidence, device data, preview captures, and unrelated projects out of the repository.
5. Tag the reviewed source as `vVERSION`, push it, and create a GitHub release at that tag. Upload the ZIP and checksum file. GitHub's source archives at the same tag provide the corresponding source under AGPL-3.0. Include any additional source archive you generate in the release's checksum file.
6. Update `version` and `sha256` in the tap's `Casks/cmf-companion.rb`. Its URL interpolates the version and points to that release's exact ZIP. Commit and push the cask only after the release is publicly downloadable.
7. Verify a download without GitHub authentication, check its SHA-256, and run `brew style` and `brew audit --cask --strict --online` against the tapped cask. Test install and uninstall in an isolated app directory, without launching a second hardware-control app.

The public install command is:

```sh
brew install --cask usamabinshahid97/tap/cmf-companion
```

Homebrew automatically clones the tap. Current Homebrew versions may ask users to trust the cask; confirmation belongs to the user. Keep this explicit rather than recommending trust of unrelated packages.

The original `usamabinshahid97/cmf-companion` tap is retained as a compatibility copy so existing installation links continue to work without an extra tap step. For each release, copy the canonical `Casks/cmf-companion.rb` from `homebrew-tap` into `homebrew-cmf-companion` and publish it there too. Its CI verifies that both casks match. If both taps are present, use the fully qualified name to avoid short-name ambiguity.

## Signing later

When a Developer ID account is ready, sign a **new version** with its Developer ID Application identity, enable the hardened runtime as needed, notarize the distribution, and staple the ticket before publishing. Keep the bundle identifier `local.usama.cmfcompanion` unless a migration is intentionally planned. Update the cask checksum and first-launch documentation with that release. Do not silently swap the current ad hoc archive or change macOS security settings in install hooks.

The current app is not submitted to Homebrew's official cask catalog. That catalog requires Gatekeeper-compatible releases; this project distributes through its own tap until those requirements and the other acceptance criteria are met.
