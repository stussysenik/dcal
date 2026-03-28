# dcal Data Layer — "Math is Code, Code is Data"

## Problem

dcal calibrates displays but forgets everything between runs. No history, no drift tracking, no way to verify past corrections. MATLAB export generates a template but doesn't verify anything. The tool is stateless when it should be learning from every measurement.

## Solution

SQLite database at `~/.dcal/dcal.db` with a typed Swift `CalibrationGraph` layer. Every command auto-captures display state. Graph traversal in Swift, analytics via SQL, MATLAB reads SQLite directly.

## Data Model

### Tables

**displays** — Digital twin per physical display
```sql
CREATE TABLE displays (
    id TEXT PRIMARY KEY,          -- vendor:model:serial hash
    name TEXT NOT NULL,           -- "Studio Display"
    vendor_id INTEGER,
    model_id INTEGER,
    serial_number INTEGER,
    native_gamma REAL DEFAULT 2.2,
    bit_depth INTEGER DEFAULT 8,
    color_space TEXT DEFAULT 'sRGB',
    first_seen TIMESTAMP,
    last_seen TIMESTAMP,
    calibration_count INTEGER DEFAULT 0,
    drift_rate REAL               -- gamma drift per week
);
```

**measurements** — Every gamma ramp snapshot
```sql
CREATE TABLE measurements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    display_id TEXT REFERENCES displays(id),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    trigger TEXT,                  -- 'status', 'analyze', 'calibrate_pre', 'calibrate_post'
    gamma_r REAL, gamma_g REAL, gamma_b REAL,
    gamma_avg REAL,
    channel_deviation REAL,
    banding_risk REAL,
    ramp_data BLOB,               -- compressed 256/1024 float array
    sample_count INTEGER
);
```

**calibrations** — Every correction applied
```sql
CREATE TABLE calibrations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    display_id TEXT REFERENCES displays(id),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    target TEXT,                   -- 'rec709', 'srgb', 'dcip3'
    target_gamma REAL,
    table_gamma_r REAL, table_gamma_g REAL, table_gamma_b REAL,
    pre_measurement_id INTEGER REFERENCES measurements(id),
    post_measurement_id INTEGER REFERENCES measurements(id),
    end_to_end_gamma REAL,
    delta_e REAL,
    passed INTEGER,               -- 1=pass, 0=fail
    method TEXT,                   -- 'lut', 'formula', 'reset'
    algorithm_version TEXT
);
```

**transforms** — Math graph edges (computation ledger)
```sql
CREATE TABLE transforms (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    calibration_id INTEGER REFERENCES calibrations(id),
    step_order INTEGER,           -- position in pipeline
    transform_type TEXT,          -- 'gamma_correction', 'bradford', 'bit_depth_optimize'
    inputs JSON,                  -- serialized computation inputs
    outputs JSON,                 -- serialized computation outputs
    duration_ms REAL
);
```

### Swift Graph Layer

```swift
// CalibrationGraph loads from SQLite, provides typed traversal
let graph = CalibrationGraph(path: "~/.dcal/dcal.db")

// Digital twin
let twin = graph.display("Studio Display")
twin.driftRate        // gamma change per week
twin.lastCalibrated   // timestamp
twin.calibrationCount // total
twin.healthScore      // computed from drift + age

// Traversal
let history = graph.calibrations(for: "Studio Display", limit: 10)
let drift = graph.timeSeries(display: "Studio Display", metric: .gamma, range: .months(6))

// Raw SQL for power users
let results = graph.query("SELECT avg(delta_e) FROM calibrations WHERE target = 'rec709'")
```

### Auto-Capture Rules

| Command | Capture |
|---------|---------|
| Any command | Upsert display in `displays` table, update `last_seen` |
| `dcal status` | Insert measurement (trigger: 'status') |
| `dcal analyze` | Insert measurement (trigger: 'analyze') with full ramp |
| `dcal calibrate` | Insert pre-measurement, calibration row, transform rows, post-measurement |
| `dcal calibrate --reset` | Insert calibration row (method: 'reset') |
| `dcal set *` | Insert calibration row (method: 'manual') |

### New CLI Commands

```
dcal history                    # calibration timeline
dcal history --since 2026-01-01 # filtered
dcal drift                      # gamma drift chart (ASCII)
dcal twin                       # digital twin summary
dcal query "SELECT ..."         # raw SQL
```

### MATLAB Integration

MATLAB reads SQLite natively:
```matlab
conn = sqlite('~/.dcal/dcal.db');
ramps = fetch(conn, 'SELECT * FROM measurements WHERE display_id = ?', display_id);
cals = fetch(conn, 'SELECT * FROM calibrations WHERE target = ''rec709''');
```

`dcal analyze --export` still generates CSV + `.m` but now queries full history from the database.

## GUI Menu Bar App

The SwiftUI menu bar app reads from the same `dcal.db`:
- Popover shows live display state from `displays` table
- Calibration results from `calibrations` table
- Drift indicator from computed `drift_rate`
- All sliders write through the same infrastructure layer
- CLI and GUI are two presentations over one data store

## Verification

- Unit tests for CalibrationGraph (in-memory SQLite)
- Integration test: run calibrate, verify rows in all 4 tables
- MATLAB: `verify_gamma.m` queries the database and independently verifies
- Drift calculation: insert synthetic measurements, verify drift_rate computation
