# CMF Companion — Liquid Glass design study

Researched and implemented on 27 October 2026. This is a native macOS menu bar utility, so the design prioritizes glanceable status, precise controls, and a stable compact layout. The research below distinguishes Apple's actual Liquid Glass material from older blur materials and from visual inspiration.

## What the primary sources establish

1. **Glass is a functional layer.** Apple's [Materials HIG](https://developer.apple.com/design/human-interface-guidelines/materials) places Liquid Glass on navigation and controls, above quieter content. It warns against making every content surface glass. `regular` preserves text legibility; `clear` is intended for visually rich media backgrounds. Decision: regular glass on the navigation capsule and listening-mode controls; ordinary material and understated fills for settings.
2. **It is more than transparency.** [Meet Liquid Glass, WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/) describes lensing, environment-aware light, and responsive interaction. Larger surfaces become more substantial. Decision: use the real public APIs rather than trying to imitate them with blur and white outlines.
3. **Geometry and typography do the quiet work.** [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/) explains concentric corner geometry, stronger left-aligned type, compact rounded rectangles on Mac, and grouping by function. Decision: a shared spacing/radius scale, optical alignment, consistent label/value columns, SF typography, and restrained use of capsules.
4. **Group related glass.** [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) documents `.glassEffect`, `.tint`, `.interactive`, `GlassEffectContainer`, and morphing identifiers. [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/) explains why nearby glass must share a sampling container. Decision: group the mode controls, avoid stacked glass cards, and retain native menus, sliders, and switches.
5. **Keep Mac behavior native.** [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/) describes the Mac's floating structural layer, control sizes, and `NSGlassEffectView`. [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) favors current system components and profiling. Decision: retain the status item/popover architecture and use new material only where the installed SDK and OS support it.
6. **Accessibility changes the material.** The Materials HIG describes adaptation to Reduce Transparency and Increase Contrast. Decision: semantic foreground colors; explicit selected marks; keyboard focus and help; a solid fallback under Reduce Transparency; no decorative perpetual animation; tab/disclosure animation removed under Reduce Motion.
7. **Direct control beats repetitive menu navigation.** Apple's [Tide Guide showcase](https://developer.apple.com/videos/play/meet-with-apple/257/) explains replacing nested dismissing menus with an anchored glass popover of direct controls. Decision: make common listening modes direct, keep deeper device lists expandable, and reserve More for app utilities.

## Contemporary Mac precedents

- **Apple Control Center / Music:** Apple's [macOS Tahoe announcement and screenshots](https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/) show coherent modules, clear active state, and floating navigation above content. Borrow the hierarchy and proportions, not every surface treatment.
- **Raycast 2:** Its [May 2026 redesign](https://www.raycast.com/blog/the-new-raycast) explicitly adopts restrained functional Liquid Glass. Its [technical account](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast) emphasizes native popup behavior and transition polish. Borrow compact typography, a calm selection state, and a quiet utility footer.
- **AirBuddy 3:** Its [official comparison](https://support.airbuddy.app/articles/what-is-the-difference-between-airbuddy-2-and-airbuddy-3/) identifies Liquid Glass in the Dashboard and Action HUD on Tahoe. The [HUD guide](https://support.airbuddy.app/articles/how-to-use-the-action-hud/) groups connection, listening modes, and battery events. Borrow the accessory-first hierarchy and glanceable status. Its hardware capabilities are not assumed to apply to CMF.
- **Things:** Its [OS 26 design post](https://culturedcode.com/things/blog/2025/09/things-for-os-26/) documents coordinated curvature, relaxed spacing, a little sidebar color, and responsive controls. Borrow the restraint and consistency between appearances.
- **SoundSource:** Its [product UI](https://www.rogueamoeba.com/soundsource/) and [interface manual](https://www.rogueamoeba.com/support/manuals/soundsource/?print=true) are useful for density, aligned rows, and contextual expansion. These sources were not used as evidence of Liquid Glass adoption.

Reference screenshots were inspected for research only. No third-party app artwork, fonts, screenshots, or source code is bundled.

## Design direction and implementation contract

**Porcelain / graphite, with a warm CMF accent.** A new device portrait and compact battery rail establish identity. A floating glass capsule navigates Sound, Controls, and Device. The primary listening selector uses actual interactive regular Liquid Glass. Equalizer, effects, gestures, and preferences use aligned quiet surfaces, avoiding the former stack of white cards. The appearance follows macOS by default, with optional app-only Light and Dark choices.

- 420-point panel width; fixed header/navigation/footer; scrolling only for deeper controls.
- A consistent 4-point spacing rhythm; 20-point content inset; concentric rounded controls.
- Product title is the single large type anchor. Settings use readable 12–14 point text; metadata stays subordinate.
- CMF orange expresses selection and emphasis. Unknown values remain em dashes or explicit “Not reported”; disconnected states retain their own helpful action path.
- The original Bluetooth transport, request timing, command serialization, readback verification, and immediate ring/fit stop behavior are unchanged.
- No automatic ringing, fit tones, login registration, firmware flashing, or phone-service claims.

## API / compatibility verification

The installed Xcode / Swift 6.4 macOS SDK was inspected directly. `Glass`, `glassEffect`, `GlassEffectContainer`, `.glass`, and `NSGlassEffectView` are public macOS 26+ APIs. The app keeps its macOS 14 deployment target, wrapping new APIs in availability checks and using standard materials before macOS 26. Standard `.regularMaterial` is identified as the older content material, not labeled Liquid Glass.

Public verification coverage and remaining limits are recorded in [CHANGELOG.md](CHANGELOG.md). Offscreen sample renders use a solid material approximation to make layout inspectable, and explicitly identify sample data; live screenshots are required to assess the actual native glass and menu rendering. Shared Glass list menus preserve the complete EQ/gesture row as a native button, with explicit accessibility labels, selected/enabled states, and keyboard navigation. System appearance is observed independently of the popover override so returning from Light/Dark to System works immediately.

## Approved Glass list — version 1.1.4

The user selected Glass list from the interactive dropdown proposal. EQ, all eight left/right gesture assignments, More, and Appearance now share one menu surface: 296-point preferred width, 22-point outer corners, 8-point inset, and 38-point minimum rows with 12-point corners. Profile/action symbols align with the text; a warm selected row and circular check remain distinct from neutral hover and keyboard focus. Custom EQ and functional groups have quiet dividers. Appearance uses a Back row within the same surface.

The menu is hosted above content inside the existing popover's owned AppKit container. A dismissal shield prevents clicks from reaching settings behind the menu, while native row buttons provide accessibility actions. Placement chooses available space above or below the trigger; constrained menus scroll, including when keyboard navigation reaches an offscreen choice. Arrow keys, Home/End, Enter/Space, Escape, Tab, and type-ahead operate the shared list. Disabled state is enforced independently of SwiftUI's native-control updates at opening and activation.

Light/Dark/System are applied to this popover's window and SwiftUI environment. The menu uses the existing regular Liquid Glass modifier on supported macOS versions and its existing material/accessibility fallbacks. System save dialogs keep their own controls. The shared list was checked with native pointer, keyboard, accessibility, appearance, and compact-height interactions; local screenshots and device diagnostics are kept out of the public source distribution.
