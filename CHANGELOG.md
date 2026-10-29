# Release notes

## 1.1.5

First public Homebrew release for CMF Buds 2 (B179), Apple Silicon, and macOS 14 or later.

- Native menu bar app with Sound, Controls, and Device panels.
- Liquid Glass on macOS 26+, a material fallback on earlier supported systems, and coordinated Glass list dropdowns.
- Battery, noise control, ANC intensity, EQ, Ultra Bass, spatial audio, gesture assignments, latency, and supported device features.
- Settings are read back from the buds; unknown or disconnected values are not shown as current.
- Recovery retains the paired control target and retry backoff across temporary stale Bluetooth flags. Nil and delayed open callbacks are handled without stranding the control connection.
- Automatic control retries do not disconnect Bluetooth audio or reset the Mac's radio. The separate Bluetooth repair action requires confirmation.

Validation: 34 core tests passed. Live readback, control-only reconnect, normal app restart, and all eight gesture menus were checked. The original case/reopen/wake sequence, extended soak, macOS sleep, and macOS 14–15 fallback still need broader hardware testing.

The app is ad hoc signed and not Apple notarized. macOS may require **Privacy & Security → Open Anyway** on first launch. Firmware installation, Nothing-account services, and phone-specific integrations remain in Nothing X. This is an unofficial community project, unaffiliated with Nothing or CMF.
