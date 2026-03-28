<div align="center">

# dcal

**Professional display calibration for macOS.**

Software gamma correction, color temperature control, and real-time display analysis — from the menu bar.

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Tests](https://img.shields.io/badge/tests-141%20passing-brightgreen)](Tests/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

## Table of Contents

- [What is dcal?](#what-is-dcal)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Color Science](#color-science)
- [Slider Pipeline](#slider-pipeline)
- [CLI](#cli)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Requirements](#requirements)
- [License](#license)

---

## What is dcal?

dcal is a macOS display calibration tool that gives you direct control over your display's gamma response. It runs as a lightweight menu bar app with a professional, DaVinci Resolve-inspired interface.

**It does three things:**

1. **Reads** your display's current gamma ramp and fits a power-law curve to show per-channel R/G/B gamma values
2. **Adjusts** brightness, contrast, and white point through real-time gamma table manipulation via CoreGraphics
3. **Targets** industry-standard transfer functions — Rec.709, DCI-P3, and sRGB — with one-click presets

```
                    ┌──────────────────────────────────┐
                    │  Studio Display        5120x2880 │
                    │  Display P3            10-bit    │
                    ├──────────────────────────────────┤
                    │  R 2.20  G 2.20  B 2.20  Avg 2.2│
                    │  Channel Deviation: 0.000        │
                    ├──────────────────────────────────┤
                    │  ADJUSTMENTS                     │
                    │  Brightness            100       │
                    │  ═══════════════════════════════○ │
                    │  Contrast               50       │
                    │  ═══════════════○═══════════════ │
                    │  White Point (K)       6500      │
                    │  ═══════════════○═══════════════ │
                    ├──────────────────────────────────┤
                    │  TARGET                          │
                    │  [Rec.709] [DCI-P3] [sRGB]      │
                    ├──────────────────────────────────┤
                    │  Settings    Refresh       Quit  │
                    └──────────────────────────────────┘
```

---

## Quick Start

```bash
# Clone and build
git clone https://github.com/stussysenik/dcal.git
cd dcal
swift build

# Launch the menu bar app
.build/arm64-apple-macosx/debug/dcal-app

# Or use the CLI
swift run dcal status
swift run dcal analyze
```

Look for the monitor icon in your menu bar. Click it to open the calibration popover.

---

## Architecture

dcal follows a strict four-layer architecture with unidirectional dependencies:

```
┌─────────────────────────────────────────────────────┐
│  GUI (SwiftUI)  │  CLI (ArgumentParser)             │   ← Presentation
├─────────────────┴───────────────────────────────────┤
│  Application — Services, Protocols, Data Models     │   ← Coordination
├─────────────────────────────────────────────────────┤
│  Infrastructure — CoreGraphics, IOKit, SQLite       │   ← Hardware I/O
├─────────────────────────────────────────────────────┤
│  Domain — Color Math, Transfer Functions, LUTs      │   ← Pure Logic
└─────────────────────────────────────────────────────┘
```

| Layer | Module | Role | Dependencies |
|-------|--------|------|--------------|
| **Domain** | `Domain` | CIE colorimetry, transfer functions (sRGB, BT.1886, PQ, HLG), LUT generation, color temperature math | None (pure math) |
| **Application** | `Application` | Service protocols (`MonitorControlling`, `CalibrationStoring`, `DeviceDiscovering`), data models | Domain |
| **Infrastructure** | `Infrastructure` | CoreGraphics gamma adapter, IOKit display detection, SQLite calibration store | Domain, Application |
| **GUI** | `dcal-app` | SwiftUI menu bar popover, observable state model, SMPTE-compliant design tokens | All layers |
| **CLI** | `dcal` | ArgumentParser commands: `status`, `analyze`, `calibrate`, `set`, `history`, `query` | All layers |

### Key Design Decisions

- **Domain layer has zero system imports** — pure `Foundation` math, 100% testable without hardware
- **Software gamma via `CGSetDisplayTransferByTable`** — works on all displays including Apple Studio Display and Pro Display XDR
- **50ms debounced slider pipeline** — smooth real-time adjustment without hammering CoreGraphics
- **CIE daylight locus** for white point — proper colorimetric conversion, not a hacked RGB tint

---

## Color Science

dcal implements professional-grade color mathematics:

| Component | Implementation | Source |
|-----------|---------------|--------|
| Transfer Functions | Power law, sRGB (IEC 61966-2-1), BT.1886 (ITU-R), PQ (ST.2084), HLG (STD-B67) | `Domain/GammaModel/TransferFunction.swift` |
| Color Spaces | sRGB/Rec.709, DCI-P3 (D65), Rec.2020 with full 3x3 matrices | `Domain/ColorMath/ColorSpaces.swift` |
| Chromatic Adaptation | Bradford transform with D50/D65/custom illuminants | `Domain/ColorMath/ChromaticAdaptation.swift` |
| Color Difference | CIEDE2000 (Delta-E 2000) | `Domain/ColorMath/DeltaE.swift` |
| White Point | CIE daylight locus (Hernandez-Andres approximation) | `Domain/ColorMath/ColorTemperature.swift` |
| LUT Generation | Identity, gamma, calibration (source→target TF mapping) | `Domain/GammaModel/LUTGenerator.swift` |
| Bit Depth | CIE L*-based perceptual uniformity optimization | `Domain/GammaModel/BitDepthOptimizer.swift` |

---

## Slider Pipeline

When you drag a slider, here's what happens:

```
Slider drag → onChange → sliderChanged() → [50ms debounce] → applyGamma()
                                                                  │
                    ┌─────────────────────────────────────────────┘
                    ▼
            RampComposer.compose(brightness, contrast, whitePointKelvin)
                    │
                    ├── Contrast → pow(2, (c-50)/50) → power-law exponent
                    ├── Brightness → scale max output [0, 1]
                    └── White Point → kelvinToRGBGains() → per-channel multiplier
                    │
                    ▼
                LUT1D (256 entries × 3 channels)
                    │
                    ▼
            GammaAdapter.writeGamma() → CGSetDisplayTransferByTable
                    │
                    ▼
            Read back → analyzeGamma() → update UI readout
```

---

## CLI

```bash
# Show connected displays and their metadata
dcal status

# Analyze the current gamma ramp
dcal analyze

# Set white point to warm (3200K studio lighting)
dcal set white-point 3200

# Set brightness
dcal set brightness 80

# View calibration history
dcal history

# Query the calibration database directly
dcal query "SELECT * FROM measurements ORDER BY timestamp DESC LIMIT 5"
```

---

## Testing

```bash
# Run all 141 tests
swift test

# Run specific suites
swift test --filter "ColorTemperature"
swift test --filter "RampComposer"
swift test --filter "TransferFunction"
swift test --filter "DeltaE"
```

Test coverage spans:
- Transfer function encode/decode roundtrips (power law, sRGB, BT.1886, PQ, HLG)
- Color space conversions (sRGB, DCI-P3, Rec.2020) with XYZ roundtrips
- LUT generation (identity, gamma, calibration) with monotonicity checks
- Chromatic adaptation (Bradford) roundtrip verification
- CIEDE2000 against Sharma et al. reference values
- Color temperature gains (range, monotonicity, D65 neutrality)
- Ramp composition (identity at neutral, brightness scaling, contrast shaping)
- SQLite store CRUD operations and drift rate computation

---

## Project Structure

```
dcal/
├── Package.swift
├── Sources/
│   ├── Domain/                    # Pure color science (zero I/O)
│   │   ├── ColorMath/
│   │   │   ├── ColorSpaces.swift         # CIE XYZ, xyY, Lab, LCh, Linear RGB
│   │   │   ├── ColorTemperature.swift    # Kelvin → RGB gains
│   │   │   ├── ChromaticAdaptation.swift # Bradford transform
│   │   │   ├── DeltaE.swift              # CIEDE2000
│   │   │   └── GammaFunctions.swift      # sRGB/Rec.709 companding
│   │   └── GammaModel/
│   │       ├── TransferFunction.swift    # EOTF: power, sRGB, BT.1886, PQ, HLG
│   │       ├── LUTGenerator.swift        # 1D LUT generation
│   │       ├── RampComposer.swift        # Slider → gamma ramp pipeline
│   │       └── BitDepthOptimizer.swift   # Perceptual uniformity
│   ├── Application/               # Service protocols & data models
│   │   ├── Services.swift                # MonitorControlling, DeviceDiscovering
│   │   ├── CalibrationStore.swift        # CalibrationStoring protocol
│   │   ├── CalibrationModels.swift       # DisplayTwin, Records
│   │   └── CaptureService.swift          # Measurement capture
│   ├── Infrastructure/            # Hardware adapters
│   │   ├── DisplayDetector.swift         # CoreGraphics + IOKit enumeration
│   │   ├── GammaAdapter.swift            # Gamma read/write/analyze
│   │   ├── SQLiteStore.swift             # Calibration database
│   │   └── Placeholder.swift             # DDC/CI stub
│   ├── App/                       # SwiftUI menu bar GUI
│   │   ├── DCalApp.swift                 # @main entry point
│   │   ├── Views/
│   │   │   ├── DCalPopover.swift         # Main popover view
│   │   │   └── DisplayStateModel.swift   # Observable state + gamma pipeline
│   │   ├── Components/
│   │   │   ├── SliderControl.swift       # Labeled slider + readout
│   │   │   ├── GammaReadout.swift        # Per-channel gamma display
│   │   │   └── PresetPicker.swift        # Rec.709 / DCI-P3 / sRGB
│   │   └── DesignSystem/
│   │       └── DesignTokens.swift        # SMPTE ST 2080-3 compliant tokens
│   └── CLI/                       # Command-line interface
│       ├── DCal.swift                    # Root command
│       ├── StatusCommand.swift
│       ├── AnalyzeCommand.swift
│       ├── CalibrateCommand.swift
│       └── SetCommand.swift
└── Tests/
    ├── DomainTests/               # 141 tests across 19 suites
    └── InfrastructureTests/
```

---

## Requirements

- macOS 14.0+
- Swift 6.2+
- Xcode 16+ (or Swift toolchain)

---

## License

MIT
