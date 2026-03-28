/* Application Layer — Service protocols and orchestration.
   Services depend on domain protocols, never concrete infrastructure types.
   All services use initializer-based dependency injection. */

import Domain

/// Protocol for controlling display hardware parameters.
public protocol MonitorControlling: Sendable {
    func setBrightness(_ value: Int, displayID: UInt32) async throws
    func setContrast(_ value: Int, displayID: UInt32) async throws
    func setColorTemperature(_ kelvin: Int, displayID: UInt32) async throws
    func getBrightness(displayID: UInt32) async throws -> Int
    func getContrast(displayID: UInt32) async throws -> Int
}

/// Protocol for managing ICC color profiles.
public protocol ProfileManaging: Sendable {
    func installProfile(at path: String) async throws
    func activeProfile(for displayID: UInt32) async throws -> String?
}

/// Protocol for discovering connected displays.
public protocol DeviceDiscovering: Sendable {
    func connectedDisplays() async throws -> [DisplayInfo]
}

/// How a display's brightness/contrast can be controlled.
public enum ControlMethod: String, Sendable, Equatable {
    case ddcCI = "DDC/CI"           // External monitors via I2C
    case appleNative = "Apple Native"  // Apple displays (Studio Display, Pro Display XDR)
    case smartThings = "SmartThings"   // Samsung TVs via REST API
    case none = "None"                 // No programmatic control available
}

/// Basic display information returned by discovery.
public struct DisplayInfo: Sendable, Equatable {
    public let id: UInt32
    public let name: String
    public let resolution: (width: Int, height: Int)
    public let bitDepth: Int
    public let controlMethod: ControlMethod
    public let isMain: Bool
    public let isBuiltIn: Bool
    public let isRetina: Bool
    public let vendorID: UInt32
    public let modelID: UInt32
    public let serialNumber: UInt32
    public let refreshRate: Double
    public let colorSpace: String       // Active color space (sRGB, P3, etc.)
    public let iccProfile: String       // Active ICC profile name
    public let estimatedNativeGamma: Double  // Panel's estimated native EOTF gamma

    /// Convenience: can this display be controlled programmatically?
    public var isControllable: Bool {
        controlMethod != .none
    }

    public init(
        id: UInt32,
        name: String,
        resolution: (width: Int, height: Int),
        bitDepth: Int,
        controlMethod: ControlMethod = .none,
        isMain: Bool = false,
        isBuiltIn: Bool = false,
        isRetina: Bool = false,
        vendorID: UInt32 = 0,
        modelID: UInt32 = 0,
        serialNumber: UInt32 = 0,
        refreshRate: Double = 0,
        colorSpace: String = "sRGB",
        iccProfile: String = "System Default",
        estimatedNativeGamma: Double = 2.2
    ) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.bitDepth = bitDepth
        self.controlMethod = controlMethod
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.isRetina = isRetina
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.refreshRate = refreshRate
        self.colorSpace = colorSpace
        self.iccProfile = iccProfile
        self.estimatedNativeGamma = estimatedNativeGamma
    }

    public static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.bitDepth == rhs.bitDepth
    }
}
