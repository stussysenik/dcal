# Progress

Tracking what's been built, what works, and what's next.

---

## Table of Contents

- [Current State](#current-state)
- [Completed Milestones](#completed-milestones)
- [What Works Today](#what-works-today)
- [Known Limitations](#known-limitations)
- [Test Coverage](#test-coverage)

---

## Current State

**Version:** 0.2.0-dev
**Branch:** `feat/data-layer-and-gui`
**Last Updated:** 2026-03-28
**Status:** GUI sliders wired to hardware gamma. Core calibration pipeline functional.

---

## Completed Milestones

### v0.1.0 — CLI + Color Science Foundation (2026-03-28)
- [x] CIE colorimetry types (XYZ, xyY, Lab, LCh, Linear RGB)
- [x] Transfer functions: power law, sRGB, BT.1886, PQ, HLG
- [x] Color space matrices: sRGB/Rec.709, DCI-P3, Rec.2020
- [x] Bradford chromatic adaptation (D50, D65, custom)
- [x] CIEDE2000 color difference
- [x] LUT generation (identity, gamma, calibration source→target)
- [x] Bit depth optimizer (CIE L* perceptual uniformity)
- [x] sRGB/Rec.709 gamma companding functions
- [x] Display detection via CoreGraphics + IOKit
- [x] Gamma ramp read/write/analyze via CoreGraphics
- [x] CLI commands: `status`, `analyze`, `calibrate`, `set`

### v0.1.1 — Data Layer (2026-03-28)
- [x] `CalibrationStoring` protocol with full CRUD
- [x] SQLite implementation with schema auto-migration
- [x] `DisplayTwin` model with health scoring
- [x] `MeasurementRecord`, `CalibrationRecord`, `TransformRecord`
- [x] `CaptureService` for automated measurement capture
- [x] Time series queries and drift rate computation
- [x] CLI commands: `history`, `drift`, `twin`, `query`

### v0.2.0 — GUI + Live Sliders (2026-03-28)
- [x] SwiftUI menu bar app (no dock icon, popover UI)
- [x] SMPTE ST 2080-3 compliant design system (achromatic surfaces)
- [x] Display metadata header (name, resolution, color space, bit depth)
- [x] Per-channel gamma readout with deviation indicator
- [x] Multi-display support with picker
- [x] Kelvin-to-RGB gains via CIE daylight locus
- [x] `RampComposer` — brightness + contrast + white point → gamma LUT
- [x] Sliders wired to `GammaAdapter.writeGamma()` with 50ms debounce
- [x] Preset picker (Rec.709, DCI-P3, sRGB) with auto-slider adjustment
- [x] Gamma restore on quit (both button and `willTerminateNotification`)
- [x] 17 new tests for color temperature and ramp composition

---

## What Works Today

| Feature | Status | Notes |
|---------|--------|-------|
| Display detection | Working | All connected displays enumerated via CoreGraphics + IOKit |
| Gamma readout | Working | Per-channel R/G/B + average, power-law fit |
| Brightness slider | Working | Scales gamma ramp max output [0, 1] |
| Contrast slider | Working | Power-law exponent: `2^((c-50)/50)`, range [0.5, 2.0] |
| White Point slider | Working | CIE daylight locus, Kelvin → per-channel RGB gains |
| Preset targets | Working | Rec.709, DCI-P3, sRGB snap sliders to standard values |
| Gamma restore | Working | On quit and app termination |
| CLI status/analyze | Working | Full display metadata and gamma analysis |
| Calibration database | Working | SQLite with measurement + calibration records |
| Multi-display | Working | Display picker appears when >1 display connected |

---

## Known Limitations

1. **DDC/CI not implemented** — `DDCActor` is a stub. External monitor hardware brightness/contrast requires IOKit I2C, which is not yet wired.
2. **Night Shift / True Tone** — dcal's gamma table overrides these macOS features. This is correct for calibration but users should be aware.
3. **Slider initial values** — Sliders start at neutral defaults (brightness=100, contrast=50, wp=6500K) rather than reading back the current display state. This is by design — they control the software correction layer.
4. **No ICC profile generation** — The tool adjusts the live gamma table but doesn't generate installable ICC profiles.
5. **macOS only** — CoreGraphics, IOKit, and SwiftUI are Apple-only. Linux/Windows would require platform-specific backends.

---

## Test Coverage

| Suite | Tests | Area |
|-------|-------|------|
| TransferFunction Power Law | 6 | Encode/decode, roundtrip, identity |
| TransferFunction sRGB | 5 | Piecewise EOTF, roundtrip, match with standalone |
| TransferFunction BT.1886 | 6 | Black level, white level, monotonicity |
| TransferFunction PQ and HLG | 4 | ST.2084, STD-B67 boundaries and roundtrips |
| sRGB Companding | 8 | Gamma functions, linear toe, roundtrips |
| xyY and XYZ Conversion | 4 | Chromaticity projection, zero handling |
| XYZ to Lab Conversion | 4 | D65 reference, black, roundtrip |
| Lab to LCh Conversion | 3 | Polar conversion, hue angle, achromatic |
| sRGB to XYZ Conversion | 6 | Primary chromaticities, black, white |
| Bradford Adaptation | 6 | Roundtrip, identity, multi-illuminant |
| Delta-E 2000 | 7 | Sharma reference pairs, symmetry |
| LUT Generator | 8 | Identity, gamma, calibration, monotonicity |
| BitDepthOptimizer | 8 | Perceptual uniformity, banding risk, near-black |
| Color Temperature Gains | 7 | D65 neutral, warm/cool, range, monotonicity |
| Ramp Composer | 10 | Identity at neutral, brightness, contrast, white point |
| SQLiteStore | 10 | CRUD, drift, time series, schema |
| DisplayTwin healthScore | 11 | Scoring penalties, caps, floors |
| MetricKind | 2 | Raw values, case count |
| displayID hashing | 5 | Stability, uniqueness, format |
| **Total** | **141** | |
