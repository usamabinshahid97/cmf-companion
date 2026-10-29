# CMF Companion

A native macOS menu bar app for **CMF Buds 2 (B179)**. Click the earbuds icon in the menu bar to open Sound, Controls, and Device settings. Written in Swift, SwiftUI, and AppKit, with no web runtime, account, server, or analytics.

Version 1.1.5 includes a sculpted device portrait, compact battery rail, floating navigation, and native Liquid Glass listening controls, including compact ANC intensity choices, on macOS 26 and later. A shared Glass list menu brings profile icons, warm selected rows, and consistent spacing to EQ, gesture assignments, app options, and Appearance. The centered top-right More button opens the app options. The appearance follows your Mac, with app-only Light and Dark choices. macOS 14–15 use a standard-material fallback. The UI respects Reduce Transparency, Increase Contrast, and Reduce Motion.

The primary-source research, current Mac app precedents, and design decisions are recorded in [LIQUID_GLASS_DESIGN.md](LIQUID_GLASS_DESIGN.md).

## Install and run

Requires an **Apple Silicon Mac**, **macOS 14 or later**, and **CMF Buds 2 (B179)**. Other CMF/Nothing models and Intel Macs are not supported by this release. Liquid Glass requires macOS 26 or later; macOS 14–15 use the material fallback.

With [Homebrew](https://brew.sh) installed:

```sh
brew install --cask usamabinshahid97/tap/cmf-companion
```

Homebrew adds the [CMF Companion tap](https://github.com/usamabinshahid97/homebrew-tap) automatically. If your Homebrew version asks whether to trust this third-party cask, review the repository and confirm if you trust it. This is a community tap maintained with the app.

Launch **CMF Companion** from Applications. This release is **ad hoc signed and is not Apple notarized**. If macOS blocks its first launch, try opening it once, then use **System Settings → Privacy & Security → Open Anyway** if you trust this release. See [Apple's instructions](https://support.apple.com/en-ie/102445). Developer ID signing and notarization are planned; Homebrew installation does not remove this first-launch requirement.

Choose **Allow** when macOS asks for Bluetooth access. Connect CMF Buds 2 in macOS Bluetooth settings; the app then connects to their separate control service automatically. Click the earbuds icon in the menu bar to open it. The app has no Dock icon.

To update, quit CMF Companion from its More menu, then run:

```sh
brew update
brew upgrade --cask usamabinshahid97/tap/cmf-companion
```

To remove it, quit the app and run `brew uninstall --cask cmf-companion`. App preferences are preserved; use `brew uninstall --cask --zap cmf-companion` to remove those too. Removing the app does not unpair your buds or reset their settings.

For a manual installation, download the Apple Silicon ZIP from [Releases](https://github.com/usamabinshahid97/cmf-companion/releases), extract it, and move **CMF Companion.app** to Applications. SHA-256 checksums and the corresponding source are provided with each release.

The top-right More menu includes optional **Launch at login**, battery percentage in the menu bar, appearance, reconnect, and diagnostic export. The footer has a refresh button. Case battery is only shown when the buds actually report it, usually while the case is open.

The app watches for the buds disconnecting in their case and reconnects their controls after they wake. Service discovery and channel opening have separate deadlines, with slower retries after failures. A temporary stale Bluetooth connected flag no longer abandons a known control-session recovery or resets its backoff; a real disconnect notification ends that recovery. Failed callbacks without channel objects are handled immediately, and an opened channel can be adopted even when its callback is missing. The recovery panel offers **Retry controls** and **Repair connection…** without claiming that a failed control attempt means audio disconnected. Repair requires confirmation because it briefly disconnects and reconnects only CMF Buds 2, pausing audio. Automatic retries never reset the Bluetooth audio connection, unpair the buds, or reset the Mac's radio.

## Controls

- Battery readings for left, right, and case, including charging state.
- Noise control: Off, Transparency, and ANC with Low, Medium, High, and Adaptive strength.
- Seven device EQ presets: Dirac Opteo, Rock, Electronic, Pop, Enhance vocals, Classical, and Custom.
- Custom three-band EQ, ±6 dB, using the B179 filter parameters (140 / 980 / 6900 Hz).
- Ultra Bass on/off and strength 1–5.
- Fixed spatial audio on/off. This model does not advertise head tracking.
- Separate left/right double tap, triple tap, tap-and-hold, and double-tap-and-hold assignments, using the model's allowed actions.
- Low latency, dual connection, and remembered multipoint device connection management.
- In-ear detection when feature 01 is present in the device's returned feature table; otherwise the app shows it as unavailable.
- Ear tip fit test, firmware version, and separate left/right Find My Buds.

Settings stay unknown until the buds report them. Each configurable setting is written, then read back; a write acknowledgement alone is not displayed as success. A reconnect clears old readings. Find My Buds requires an in-app remove-earbuds confirmation and sends stop after three seconds, when the popover closes, and at normal app termination. Ringing and fit-test tones are never started automatically.

Firmware installation, Nothing-account services, ChatGPT/News phone integrations, and phone-specific features remain in the official Nothing X app. The firmware update protocol has not been implemented. The app does not claim to provide unsupported device capabilities or add codecs to macOS.

## Build

Requires Xcode with the macOS 26 or newer SDK and Swift 6. The app runs on macOS 14 or later. The current build targets Apple Silicon; building on an Intel Mac produces an Intel app.

```sh
swift test
bash scripts/build.sh
```

The build script creates `dist/CMF Companion.app`, its icon, license notices, and an ad hoc code signature. Release packaging and Homebrew maintenance are documented in [DISTRIBUTION.md](DISTRIBUTION.md). Ad hoc signing checks bundle integrity; it does not establish an Apple-verified publisher or provide notarization.

For UI QA without contacting any Bluetooth device:

```sh
"dist/CMF Companion.app/Contents/MacOS/CMFCompanion" --render-previews /tmp/cmf-previews
```

The previews explicitly label their sample data. They cover both appearances, every tab, custom EQ, disconnected and unknown states, and compact height. These are layout snapshots with a solid glass approximation because offscreen AppKit capture cannot reproduce the live material; use the actual popover to judge glass, menus, and interaction. `--preview` runs a sample-data view with no Bluetooth access. `--diagnostics /absolute/path/status.json` writes a local developer status file containing reported settings and bounded protocol logs; no Bluetooth addresses, serial numbers, or raw device payloads are included. Normal runs do not write this file.

## Troubleshooting

If the audio is connected but settings are unavailable, close Nothing X or other earbud-control apps and use **Reconnect to buds**. Only one application may be able to hold the control socket at a time. If access was denied, enable CMF Companion under System Settings → Privacy & Security → Bluetooth.

Use **Save diagnostics** from the app menu to save the firmware, connection state, and recent command IDs. The log contains no raw Bluetooth payloads. Support is intentionally limited to paired devices named `CMF Buds 2`; other models have different capability and gesture maps.

This is an early community release. All 34 core tests pass, and live checks cover settings readback, control-only reconnect, normal app restart, and all eight gesture menus. The original case/reopen/wake sequence, long-duration connection soak, macOS sleep, and the macOS 14–15 fallback still need broader hardware testing. The RFCOMM control service can be unavailable even while Bluetooth audio is connected; report persistent failures with a diagnostic export in [Issues](https://github.com/usamabinshahid97/cmf-companion/issues). Review diagnostic text before sharing it publicly.

## Protocol and credits

The app resolves the Nothing **NT LINK** RFCOMM service through Bluetooth SDP, UUID `AEAC4A03-DFF5-498F-843A-34487CF133EB`. Each attempt owns its SDP target and channel delegate so a late callback cannot affect a replacement connection. The channel owner handles inline completion, existing open channels, partial failures, and reentrant close callbacks. It validates CRC16, reassembles fragmented packets, queues requests, and matches replies by both operation ID and command. It uses B179's listening-mode EQ commands rather than the Nothing Ear preset commands.

References and license notices are in [THIRD_PARTY.md](THIRD_PARTY.md). This project is licensed under AGPL-3.0; see [LICENSE](LICENSE).
