# Roadmap

Where dcal is headed. Organized by phase, roughly in priority order.

---

## Table of Contents

- [Phase 1: Core Calibration (Done)](#phase-1-core-calibration-done)
- [Phase 2: DDC/CI Hardware Control](#phase-2-ddcci-hardware-control)
- [Phase 3: Automated Calibration Workflow](#phase-3-automated-calibration-workflow)
- [Phase 4: ICC Profile Generation](#phase-4-icc-profile-generation)
- [Phase 5: Advanced Display Features](#phase-5-advanced-display-features)
- [Phase 6: Multi-Platform](#phase-6-multi-platform)
- [Ideas & Explorations](#ideas--explorations)

---

## Phase 1: Core Calibration (Done)

Everything needed for software-based gamma correction from the menu bar.

- [x] CIE colorimetry engine (XYZ, Lab, LCh, Delta-E 2000)
- [x] Transfer function library (sRGB, BT.1886, PQ, HLG)
- [x] Color space matrices (sRGB, DCI-P3, Rec.2020)
- [x] CoreGraphics gamma read/write/analyze
- [x] Display detection (CGGetActiveDisplayList + IOKit metadata)
- [x] LUT generation (identity, gamma, calibration)
- [x] Bit depth perceptual optimization
- [x] SwiftUI menu bar app with live sliders
- [x] Brightness / Contrast / White Point → gamma ramp pipeline
- [x] Preset targets: Rec.709, DCI-P3, sRGB
- [x] SQLite calibration ledger with measurement history
- [x] CLI: status, analyze, calibrate, set, history, query
- [x] 141 tests across 19 suites

---

## Phase 2: DDC/CI Hardware Control

Direct hardware brightness/contrast control for external monitors via I2C.

- [ ] IOKit I2C DDC/CI implementation in `DDCActor`
  - VCP code `0x10` — Brightness
  - VCP code `0x12` — Contrast
  - VCP code `0x0C` — Color Temperature
- [ ] DDC capability string parsing
- [ ] Per-display control method routing (DDC vs. software gamma)
- [ ] Hardware brightness slider (0-100) for DDC-capable monitors
- [ ] Samsung SmartThings API integration for TV control
- [ ] Fallback chain: DDC → Apple Native → software gamma

**Why this matters:** Software gamma can't increase brightness beyond the display's native maximum. DDC/CI controls the backlight directly, giving true hardware brightness control on supported monitors.

---

## Phase 3: Automated Calibration Workflow

One-click calibration that measures, computes, and applies the correction.

- [ ] Guided calibration wizard in the GUI
  - Step 1: Measure native gamma (read current ramp)
  - Step 2: Select target (Rec.709, DCI-P3, sRGB, custom)
  - Step 3: Compute calibration LUT via `LUTGenerator.generateCalibrationLUT()`
  - Step 4: Apply and verify (read back, compute Delta-E)
- [ ] Before/after comparison view
- [ ] Calibration scheduling (periodic re-calibration reminders)
- [ ] Drift detection and alerting (using `DisplayTwin.driftRate`)
- [ ] Calibration report export (PDF/JSON)

---

## Phase 4: ICC Profile Generation

Generate and install system-level ICC profiles from calibration data.

- [ ] ICC profile v4 binary writer
  - Header, tag table, TRC curves, matrix columns
  - Chromatic adaptation tag for non-D50 white points
- [ ] Install profile via `ColorSync` framework
- [ ] Per-display profile management (install, activate, remove)
- [ ] Profile comparison tool (overlay two profiles' TRCs)
- [ ] Export .icc files for use in other applications

**Why this matters:** Gamma table changes are volatile (lost on reboot). ICC profiles persist and are respected by color-managed applications (Photoshop, DaVinci Resolve, etc.).

---

## Phase 5: Advanced Display Features

Professional features for color-critical workflows.

- [ ] 3D LUT support (inter-channel correction for color crosstalk)
- [ ] Colorimeter integration (i1 Display Pro, SpyderX via USB HID)
- [ ] Ambient light compensation
- [ ] Uniformity correction (edge-to-edge luminance mapping)
- [ ] Gamut mapping visualization (CIE diagram with display triangle overlay)
- [ ] HDR metadata display (MaxCLL, MaxFALL, EOTF)
- [ ] PQ/HLG tone mapping preview

---

## Phase 6: Multi-Platform

Extend beyond macOS.

- [ ] **Linux support**
  - X11: `xrandr --gamma` / `XF86VidModeSetGamma`
  - Wayland: `wl-output` gamma control
  - DDC: `ddcutil` integration
  - GUI: GTK4 or terminal UI (the Domain layer is already platform-independent)
- [ ] **Windows support**
  - Win32: `SetDeviceGammaRamp`
  - DDC: `PhysicalMonitorEnumerationAPI`
  - GUI: WinUI 3 or cross-platform framework

---

## Ideas & Explorations

Things worth investigating but not yet committed to.

- **Pattern generator** — Full-screen test patterns (grayscale ramp, color bars, SMPTE, cross-hatch) for visual verification
- **Display fingerprinting** — Identify individual display units by their gamma signature for portable calibration profiles
- **Network sync** — Synchronize calibration settings across multiple machines viewing the same content
- **Resolve integration** — Export 3D LUTs in `.cube` format for DaVinci Resolve
- **A/B comparison** — Toggle between calibrated and uncalibrated with a keyboard shortcut
- **Spectral rendering** — Model display primaries as spectral power distributions for maximum accuracy
- **Apple ProRes RAW** — White balance metadata extraction for camera-to-display color matching
