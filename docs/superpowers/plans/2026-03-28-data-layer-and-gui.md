# dcal Data Layer + GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SQLite persistence (computation ledger, digital twins, auto-capture) and a SwiftUI menu bar app, both reading from the same `~/.dcal/dcal.db`.

**Architecture:** SQLite via system C API (zero deps). `CalibrationStoring` protocol in Application layer, `SQLiteStore` in Infrastructure. Auto-capture on every CLI invocation. Separate `dcal-app` executable target for the GUI sharing Domain/Application/Infrastructure.

**Tech Stack:** Swift 6.2, SQLite3 (system), SwiftUI MenuBarExtra, ArgumentParser, Swift Testing

---

### Task 1: Shared AsyncBridge utility

**Files:**
- Create: `Sources/CLI/AsyncBridge.swift`
- Modify: `Sources/CLI/StatusCommand.swift` (remove local ResultBox)
- Modify: `Sources/CLI/CalibrateCommand.swift` (remove local CalBox)
- Modify: `Sources/CLI/AnalyzeCommand.swift` (remove local AnalyzeBox)

- [ ] **Step 1: Create shared async bridge**

```swift
// Sources/CLI/AsyncBridge.swift
import Foundation

final class AsyncBox<T: Sendable>: @unchecked Sendable {
    var value: Result<T, Error>?
}

func syncBridge<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = AsyncBox<T>()
    Task { @Sendable in
        do { box.value = .success(try await block()) }
        catch { box.value = .failure(error) }
        sem.signal()
    }
    sem.wait()
    switch box.value! {
    case .success(let v): return v
    case .failure(let e): throw e
    }
}
```

- [ ] **Step 2: Remove duplicate boxes from StatusCommand, CalibrateCommand, AnalyzeCommand**

Replace `syncRun`/`syncCalibrate`/`syncAnalyze` calls with `syncBridge` in all three files. Delete the local `ResultBox`/`CalBox`/`AnalyzeBox` types.

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: Build succeeds, 88 tests pass

- [ ] **Step 4: Commit**

```
git add Sources/CLI/AsyncBridge.swift Sources/CLI/StatusCommand.swift Sources/CLI/CalibrateCommand.swift Sources/CLI/AnalyzeCommand.swift
git commit -m "refactor: consolidate async bridge into shared utility"
```

---

### Task 2: CalibrationModels (Application layer data types)

**Files:**
- Create: `Sources/Application/CalibrationModels.swift`

- [ ] **Step 1: Write the test**

Create `Tests/DomainTests/CalibrationModelsTests.swift`:
```swift
import Testing
@testable import Application

@Suite("DisplayTwin")
struct DisplayTwinTests {
    @Test func healthScoreExcellentForRecentCalibration() {
        let twin = DisplayTwin(id: "test", name: "Test", vendorID: 0, modelID: 0, serialNumber: 0, nativeGamma: 2.2, bitDepth: 10, colorSpace: "P3", firstSeen: Date(), lastSeen: Date(), calibrationCount: 5, driftRate: 0.001)
        #expect(twin.healthScore > 0.8)
    }

    @Test func healthScoreDropsWhenNeverCalibrated() {
        let twin = DisplayTwin(id: "test", name: "Test", vendorID: 0, modelID: 0, serialNumber: 0, nativeGamma: 2.2, bitDepth: 8, colorSpace: "sRGB", firstSeen: Date(), lastSeen: Date().addingTimeInterval(-86400 * 60), calibrationCount: 0, driftRate: nil)
        #expect(twin.healthScore < 0.6)
    }
}

@Suite("Display ID")
struct DisplayIDTests {
    @Test func stableAcrossInvocations() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xAE3A, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x0610, modelID: 0xAE3A, serialNumber: 12345)
        #expect(id1 == id2)
    }

    @Test func differentForDifferentDisplays() {
        let id1 = displayID(vendorID: 0x0610, modelID: 0xAE3A, serialNumber: 12345)
        let id2 = displayID(vendorID: 0x10AC, modelID: 0x1234, serialNumber: 67890)
        #expect(id1 != id2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "DisplayTwin|DisplayID"`
Expected: FAIL — types don't exist yet

- [ ] **Step 3: Implement CalibrationModels.swift**

Create `Sources/Application/CalibrationModels.swift` with:
- `DisplayTwin` struct (with `healthScore` computed property)
- `MeasurementRecord` struct
- `CalibrationRecord` struct
- `TransformRecord` struct
- `MetricKind` enum
- `displayID(vendorID:modelID:serialNumber:)` function (djb2 hash)

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test`
Expected: All pass (88 existing + new)

- [ ] **Step 5: Commit**

---

### Task 3: CalibrationStoring protocol

**Files:**
- Create: `Sources/Application/CalibrationStore.swift`

- [ ] **Step 1: Create the protocol**

```swift
public protocol CalibrationStoring: Sendable {
    func upsertDisplay(_ info: DisplayInfo) throws
    func display(id: String) throws -> DisplayTwin?
    func allDisplays() throws -> [DisplayTwin]
    @discardableResult func insertMeasurement(_ m: MeasurementRecord) throws -> Int64
    func measurements(displayID: String, limit: Int) throws -> [MeasurementRecord]
    @discardableResult func insertCalibration(_ c: CalibrationRecord) throws -> Int64
    func calibrations(displayID: String, limit: Int) throws -> [CalibrationRecord]
    func insertTransforms(_ transforms: [TransformRecord], calibrationID: Int64) throws
    func timeSeries(displayID: String, metric: MetricKind, since: Date) throws -> [(date: Date, value: Double)]
    func computeDriftRate(displayID: String) throws -> Double?
    func query(_ sql: String) throws -> [[String: String]]
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Compiles (protocol only, no implementation yet)

- [ ] **Step 3: Commit**

---

### Task 4: SQLiteStore implementation

**Files:**
- Modify: `Package.swift` (add sqlite3 linker setting, add test target)
- Create: `Sources/Infrastructure/SQLiteStore.swift`
- Create: `Sources/Infrastructure/RampCompression.swift`
- Create: `Tests/InfrastructureTests/SQLiteStoreTests.swift`

- [ ] **Step 1: Update Package.swift**

Add to Infrastructure target: `linkerSettings: [.linkedLibrary("sqlite3")]`
Add new test target: `InfrastructureTests` depending on `Domain`, `Application`, `Infrastructure`

- [ ] **Step 2: Write SQLiteStore tests (in-memory)**

```swift
import Testing
@testable import Infrastructure
@testable import Application

@Suite("SQLiteStore")
struct SQLiteStoreTests {
    @Test func createsSchemaOnInit() throws {
        let store = try SQLiteStore(inMemory: true)
        let results = try store.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        let tables = results.map { $0["name"]! }
        #expect(tables.contains("displays"))
        #expect(tables.contains("measurements"))
        #expect(tables.contains("calibrations"))
        #expect(tables.contains("transforms"))
    }

    @Test func upsertAndRetrieveDisplay() throws {
        let store = try SQLiteStore(inMemory: true)
        let info = makeTestDisplayInfo()
        try store.upsertDisplay(info)
        let twin = try store.display(id: displayID(vendorID: info.vendorID, modelID: info.modelID, serialNumber: info.serialNumber))
        #expect(twin != nil)
        #expect(twin?.name == "Test Display")
    }

    @Test func insertAndQueryMeasurement() throws {
        let store = try SQLiteStore(inMemory: true)
        let info = makeTestDisplayInfo()
        try store.upsertDisplay(info)
        let did = displayID(vendorID: info.vendorID, modelID: info.modelID, serialNumber: info.serialNumber)
        let m = MeasurementRecord(id: nil, displayID: did, timestamp: Date(), trigger: "test", gammaR: 2.2, gammaG: 2.2, gammaB: 2.2, gammaAvg: 2.2, channelDeviation: 0.0, bandingRisk: 0.5, rampData: nil, sampleCount: 256)
        let id = try store.insertMeasurement(m)
        #expect(id > 0)
        let results = try store.measurements(displayID: did, limit: 10)
        #expect(results.count == 1)
    }

    @Test func insertCalibrationWithPrePost() throws {
        let store = try SQLiteStore(inMemory: true)
        let info = makeTestDisplayInfo()
        try store.upsertDisplay(info)
        let did = displayID(vendorID: info.vendorID, modelID: info.modelID, serialNumber: info.serialNumber)
        let preID = try store.insertMeasurement(MeasurementRecord(id: nil, displayID: did, timestamp: Date(), trigger: "calibrate_pre", gammaR: 1.0, gammaG: 1.0, gammaB: 1.0, gammaAvg: 1.0, channelDeviation: 0.0, bandingRisk: nil, rampData: nil, sampleCount: 256))
        let postID = try store.insertMeasurement(MeasurementRecord(id: nil, displayID: did, timestamp: Date(), trigger: "calibrate_post", gammaR: 1.09, gammaG: 1.09, gammaB: 1.09, gammaAvg: 1.09, channelDeviation: 0.0, bandingRisk: nil, rampData: nil, sampleCount: 256))
        let cal = CalibrationRecord(id: nil, displayID: did, timestamp: Date(), target: "rec709", targetGamma: 2.4, tableGammaR: 1.09, tableGammaG: 1.09, tableGammaB: 1.09, preMeasurementID: preID, postMeasurementID: postID, endToEndGamma: 2.4, deltaE: 0.8, passed: true, method: "lut", algorithmVersion: "0.1.0")
        let calID = try store.insertCalibration(cal)
        #expect(calID > 0)
    }

    @Test func driftRateRequiresMultipleMeasurements() throws {
        let store = try SQLiteStore(inMemory: true)
        let info = makeTestDisplayInfo()
        try store.upsertDisplay(info)
        let did = displayID(vendorID: info.vendorID, modelID: info.modelID, serialNumber: info.serialNumber)
        let drift = try store.computeDriftRate(displayID: did)
        #expect(drift == nil) // not enough data
    }
}

func makeTestDisplayInfo() -> DisplayInfo {
    DisplayInfo(id: 1, name: "Test Display", resolution: (3840, 2160), bitDepth: 10, controlMethod: .ddcCI, vendorID: 0x10AC, modelID: 0x1234, serialNumber: 12345, estimatedNativeGamma: 2.2)
}
```

- [ ] **Step 3: Implement SQLiteStore**

Full implementation with: schema creation, WAL mode, migration system, all CRUD methods, drift rate computation via linear regression on time-series measurements.

- [ ] **Step 4: Implement RampCompression**

`compressRamp(_:)` and `decompressRamp(_:sampleCount:)` using zlib via Foundation's `NSData.compressed`.

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: 88 existing + ~10 new all pass

- [ ] **Step 6: Commit**

---

### Task 5: CaptureService and auto-capture wiring

**Files:**
- Create: `Sources/Application/CaptureService.swift`
- Create: `Sources/CLI/DataLayer.swift`
- Modify: `Sources/CLI/StatusCommand.swift`
- Modify: `Sources/CLI/CalibrateCommand.swift`
- Modify: `Sources/CLI/AnalyzeCommand.swift`

- [ ] **Step 1: Create CaptureService**

Orchestrates silent recording. `captureDisplays()`, `captureMeasurement()`, `captureCalibration()`.

- [ ] **Step 2: Create DataLayer factory**

```swift
enum DataLayer {
    static func store() -> CalibrationStoring? { try? SQLiteStore() }
    static func captureService() -> CaptureService? {
        guard let store = store() else { return nil }
        return CaptureService(store: store, detector: DisplayDetector())
    }
}
```

- [ ] **Step 3: Wire auto-capture into StatusCommand**

After display detection, silently call `capture.captureMeasurement(trigger: "status")`. Wrapped in `try?` — never fails the command.

- [ ] **Step 4: Wire auto-capture into CalibrateCommand**

Record pre-measurement, calibration record, transform steps, post-measurement. Most complex integration.

- [ ] **Step 5: Wire auto-capture into AnalyzeCommand**

Record measurement with trigger "analyze".

- [ ] **Step 6: Build, test, verify database created**

```bash
swift build -c release && cp .build/release/dcal ~/.local/bin/dcal
dcal status
ls -la ~/.dcal/dcal.db  # should exist now
dcal query "SELECT * FROM displays"
```

- [ ] **Step 7: Commit**

---

### Task 6: New CLI commands (history, drift, twin, query)

**Files:**
- Create: `Sources/CLI/HistoryCommand.swift`
- Create: `Sources/CLI/DriftCommand.swift`
- Create: `Sources/CLI/TwinCommand.swift`
- Create: `Sources/CLI/QueryCommand.swift`
- Modify: `Sources/CLI/DCal.swift` (register subcommands)

- [ ] **Step 1: Create all four commands**

Each queries SQLiteStore and formats output. DriftCommand includes ASCII sparkline rendering.

- [ ] **Step 2: Register in DCal.swift**

Add `History.self, Drift.self, Twin.self, Query.self` to subcommands.

- [ ] **Step 3: Build, install, test all commands**

```bash
swift build -c release && cp .build/release/dcal ~/.local/bin/dcal
dcal history
dcal twin
dcal query "SELECT COUNT(*) FROM measurements"
```

- [ ] **Step 4: Commit**

---

### Task 7: GUI — Package.swift + minimal app

**Files:**
- Modify: `Package.swift` (add dcal-app target)
- Create: `Sources/App/DCalApp.swift`
- Create: `Sources/App/Info.plist`

- [ ] **Step 1: Add GUI target to Package.swift**

```swift
.executableTarget(
    name: "dcal-app",
    dependencies: ["Domain", "Application", "Infrastructure"],
    path: "Sources/App",
    resources: [.copy("Info.plist")]
),
```

- [ ] **Step 2: Create minimal DCalApp.swift**

```swift
import SwiftUI
@main struct DCalApp: App {
    var body: some Scene {
        MenuBarExtra("dcal", systemImage: "display") {
            Text("dcal v0.1.0").padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Create Info.plist with LSUIElement=true**

- [ ] **Step 4: Build and verify menu bar icon appears**

```bash
swift build --target dcal-app && .build/debug/dcal-app
```

- [ ] **Step 5: Commit**

---

### Task 8: GUI — Design system tokens

**Files:**
- Create: `Sources/App/DesignSystem/DesignTokens.swift`
- Create: `Sources/App/DesignSystem/VisualEffect.swift`

- [ ] **Step 1: Create all Color, Font, Layout tokens**

Achromatic surfaces (`Color(white:)`), SF Pro/Mono typography, 8pt grid constants.

- [ ] **Step 2: Create NSVisualEffectView wrapper**

Optional vibrancy for users who prefer native macOS feel.

- [ ] **Step 3: Commit**

---

### Task 9: GUI — Components

**Files:**
- Create: `Sources/App/Components/SliderControl.swift`
- Create: `Sources/App/Components/SegmentedControl.swift`
- Create: `Sources/App/Components/DisplayRow.swift`
- Create: `Sources/App/Components/CDLReadout.swift`
- Create: `Sources/App/Components/MetricPill.swift`

- [ ] **Step 1: Build all 5 reusable components**

Each is a standalone SwiftUI view using design tokens.

- [ ] **Step 2: Commit**

---

### Task 10: GUI — Views + state model + wiring

**Files:**
- Create: `Sources/App/Views/DisplayStateModel.swift`
- Create: `Sources/App/Views/DCalPopover.swift`
- Create: `Sources/App/Views/HeaderSection.swift`
- Create: `Sources/App/Views/ControlsSection.swift`
- Create: `Sources/App/Views/FooterSection.swift`
- Create: `Sources/App/Services/DisplayService.swift`
- Modify: `Sources/App/DCalApp.swift` (wire state + popover)

- [ ] **Step 1: Create DisplayStateModel (@Observable)**

Holds display list, gamma readings, calibration state. Refreshes from Infrastructure layer.

- [ ] **Step 2: Create DisplayService**

Wraps DisplayDetector + GammaAdapter for GUI use.

- [ ] **Step 3: Create all view sections**

Header, Controls (sliders + target picker + calibrate button), Footer.

- [ ] **Step 4: Assemble DCalPopover**

Vertical stack of all sections in 340pt panel.

- [ ] **Step 5: Wire into DCalApp**

Pass state model, add `.task { await state.refresh() }`.

- [ ] **Step 6: Build and verify full popover renders**

```bash
swift build --target dcal-app && .build/debug/dcal-app
```

- [ ] **Step 7: Install both binaries**

```bash
swift build -c release
cp .build/release/dcal ~/.local/bin/dcal
cp .build/release/dcal-app ~/.local/bin/dcal-app
```

- [ ] **Step 8: Commit**

---

### Task 11: Final verification

- [ ] **Step 1: Run full test suite**

```bash
swift test
```
Expected: All tests pass (88 existing + ~15 new data layer tests)

- [ ] **Step 2: CLI integration check**

```bash
dcal status           # creates database + records measurement
dcal analyze          # records measurement
dcal calibrate --dry-run  # does not record (dry run)
dcal history          # shows timeline
dcal twin             # shows digital twin
dcal query "SELECT COUNT(*) FROM measurements"  # should show count
```

- [ ] **Step 3: GUI check**

```bash
dcal-app              # menu bar icon appears, popover shows live data
```

- [ ] **Step 4: Cross-process check**

Run `dcal-app` in background, then `dcal calibrate` in terminal. GUI should update.

- [ ] **Step 5: MATLAB check**

```matlab
conn = sqlite('~/.dcal/dcal.db');
data = fetch(conn, 'SELECT * FROM measurements');
```
