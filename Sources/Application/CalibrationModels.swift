/* Application Layer — Calibration database data types.
   These models represent the calibration history stored by SQLiteStore
   and queried by CLI commands and the GUI.  All types are Sendable for
   safe actor-boundary crossing in Swift 6.2 strict concurrency. */

import Foundation

// MARK: - DisplayTwin

/// Digital twin summary for a physical display.
///
/// A DisplayTwin captures the identity, characteristics, and calibration
/// history of a monitor.  The `healthScore` computed property gives a
/// quick 0–1 indicator of whether the display needs attention:
///   - Recent calibrations and low drift keep the score near 1.0.
///   - Stale calibrations, high drift, or zero calibrations penalise it.
public struct DisplayTwin: Sendable, Equatable {
    public let id: String
    public let name: String
    public let vendorID: UInt32
    public let modelID: UInt32
    public let serialNumber: UInt32
    public let nativeGamma: Double
    public let bitDepth: Int
    public let colorSpace: String
    public let firstSeen: Date
    public let lastSeen: Date
    public let calibrationCount: Int
    /// Gamma change per week, nil when insufficient data (< 2 measurements).
    public let driftRate: Double?

    /// Quick health indicator in [0, 1].
    ///
    /// Scoring rules (penalties are cumulative, floor at 0):
    /// - > 30 days since last seen: −0.3
    /// - > 7 days since last seen:  −0.1
    /// - |driftRate| > 0.05:        −0.3
    /// - calibrationCount == 0:     −0.2
    public var healthScore: Double {
        var score = 1.0
        let daysSinceCalibration = Date().timeIntervalSince(lastSeen) / 86400.0
        if daysSinceCalibration > 30 { score -= 0.3 }
        else if daysSinceCalibration > 7 { score -= 0.1 }
        if let drift = driftRate, abs(drift) > 0.05 { score -= 0.3 }
        if calibrationCount == 0 { score -= 0.2 }
        return max(0.0, min(1.0, score))
    }

    public init(
        id: String,
        name: String,
        vendorID: UInt32,
        modelID: UInt32,
        serialNumber: UInt32,
        nativeGamma: Double,
        bitDepth: Int,
        colorSpace: String,
        firstSeen: Date,
        lastSeen: Date,
        calibrationCount: Int,
        driftRate: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.nativeGamma = nativeGamma
        self.bitDepth = bitDepth
        self.colorSpace = colorSpace
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.calibrationCount = calibrationCount
        self.driftRate = driftRate
    }
}

// MARK: - MeasurementRecord

/// A snapshot of the gamma ramp at a point in time.
///
/// Every time dcal reads the GPU gamma tables this record captures
/// the full per-channel state.  The `rampHash` provides a compact
/// fingerprint for duplicate detection.
public struct MeasurementRecord: Sendable, Equatable {
    public let id: String
    public let displayID: String
    public let timestamp: Date
    public let gammaR: Double
    public let gammaG: Double
    public let gammaB: Double
    /// Combined gamma — typically the average of the three channels.
    public let gamma: Double
    /// Maximum absolute difference between per-channel gammas.
    public let channelDeviation: Double
    /// Banding risk score [0, 1] at the time of measurement.
    public let bandingRisk: Double
    /// SHA-256 prefix of the raw ramp data for deduplication.
    public let rampHash: String

    public init(
        id: String,
        displayID: String,
        timestamp: Date,
        gammaR: Double,
        gammaG: Double,
        gammaB: Double,
        gamma: Double,
        channelDeviation: Double,
        bandingRisk: Double,
        rampHash: String
    ) {
        self.id = id
        self.displayID = displayID
        self.timestamp = timestamp
        self.gammaR = gammaR
        self.gammaG = gammaG
        self.gammaB = gammaB
        self.gamma = gamma
        self.channelDeviation = channelDeviation
        self.bandingRisk = bandingRisk
        self.rampHash = rampHash
    }
}

// MARK: - CalibrationRecord

/// A correction that was applied to a display's gamma ramp.
///
/// Each record captures the before/after gamma values and whether the
/// calibration completed successfully.  Failed calibrations (e.g. from
/// a DDC/CI timeout) are kept for diagnostic value.
public struct CalibrationRecord: Sendable, Equatable {
    public let id: String
    public let displayID: String
    public let timestamp: Date
    public let targetGamma: Double
    public let measuredGammaBefore: Double
    public let measuredGammaAfter: Double
    public let success: Bool
    /// Human-readable description of the correction method.
    public let method: String
    /// Duration of the calibration operation in seconds.
    public let durationSeconds: Double

    public init(
        id: String,
        displayID: String,
        timestamp: Date,
        targetGamma: Double,
        measuredGammaBefore: Double,
        measuredGammaAfter: Double,
        success: Bool,
        method: String,
        durationSeconds: Double
    ) {
        self.id = id
        self.displayID = displayID
        self.timestamp = timestamp
        self.targetGamma = targetGamma
        self.measuredGammaBefore = measuredGammaBefore
        self.measuredGammaAfter = measuredGammaAfter
        self.success = success
        self.method = method
        self.durationSeconds = durationSeconds
    }
}

// MARK: - TransformRecord

/// An entry in the computation ledger.
///
/// Every LUT computation or transform pipeline step is logged so
/// the user can audit exactly what dcal did and reproduce it later.
public struct TransformRecord: Sendable, Equatable {
    public let id: String
    public let calibrationID: String
    public let timestamp: Date
    /// Pipeline step index (0-based).
    public let stepIndex: Int
    /// Human-readable label for this step (e.g. "powerLaw", "sRGB", "bt1886").
    public let transformType: String
    /// JSON-encoded parameters for reproducibility.
    public let parameters: String
    /// Input gamma before this step.
    public let inputGamma: Double
    /// Output gamma after this step.
    public let outputGamma: Double

    public init(
        id: String,
        calibrationID: String,
        timestamp: Date,
        stepIndex: Int,
        transformType: String,
        parameters: String,
        inputGamma: Double,
        outputGamma: Double
    ) {
        self.id = id
        self.calibrationID = calibrationID
        self.timestamp = timestamp
        self.stepIndex = stepIndex
        self.transformType = transformType
        self.parameters = parameters
        self.inputGamma = inputGamma
        self.outputGamma = outputGamma
    }
}

// MARK: - MetricKind

/// Queryable metric kinds for time-series analysis.
///
/// Each case maps to a column or derived value in the calibration
/// database that can be plotted, aggregated, or alerted on.
public enum MetricKind: String, Sendable, Equatable, CaseIterable {
    /// Combined gamma value (average of R/G/B).
    case gamma
    /// Red channel gamma.
    case gammaR
    /// Green channel gamma.
    case gammaG
    /// Blue channel gamma.
    case gammaB
    /// Maximum deviation between per-channel gammas.
    case channelDeviation
    /// Banding risk score [0, 1].
    case bandingRisk
}

// MARK: - Display ID Generation

/// Generates a stable 16-character hex identifier for a physical display.
///
/// Uses the djb2 hash function seeded with vendorID, modelID, and
/// serialNumber.  The same physical display always produces the same
/// ID regardless of which port it's plugged into or which macOS
/// display-ID it receives.
///
/// - Parameters:
///   - vendorID: USB/EDID vendor identifier (e.g. 0x0610 for Apple).
///   - modelID: USB/EDID product identifier.
///   - serialNumber: EDID serial number (may be 0 for some panels).
/// - Returns: A 16-character lowercase hex string.
public func displayID(vendorID: UInt32, modelID: UInt32, serialNumber: UInt32) -> String {
    // Encode the three IDs into a byte sequence for hashing.
    // Each UInt32 contributes 4 bytes in big-endian order.
    var bytes: [UInt8] = []
    bytes.append(contentsOf: withUnsafeBytes(of: vendorID.bigEndian) { Array($0) })
    bytes.append(contentsOf: withUnsafeBytes(of: modelID.bigEndian) { Array($0) })
    bytes.append(contentsOf: withUnsafeBytes(of: serialNumber.bigEndian) { Array($0) })

    // djb2 hash — simple, fast, and well-distributed for short inputs.
    // We run two independent seeds to get 128 bits (16 hex chars).
    let hash1 = djb2(bytes: bytes, seed: 5381)
    let hash2 = djb2(bytes: bytes, seed: 0x9E3779B9)

    // Combine both 64-bit hashes into a single 16-char hex string.
    return String(format: "%08x%08x",
                  UInt32(truncatingIfNeeded: hash1),
                  UInt32(truncatingIfNeeded: hash2))
}

/// Classic djb2 hash function operating on a byte sequence.
///
/// `hash = seed; for each byte: hash = hash * 33 + byte`
/// Overflow is expected and handled by `&*` / `&+` operators.
private func djb2(bytes: [UInt8], seed: UInt64) -> UInt64 {
    var hash = seed
    for byte in bytes {
        hash = hash &* 33 &+ UInt64(byte)
    }
    return hash
}
