/* Infrastructure Layer — Actor-based adapters for hardware I/O.
   Each adapter implements a domain/application protocol.
   Actors provide thread-safe, per-device isolation. */

import Domain
import Application

/// Placeholder for DDC/CI communication actor.
/// Will implement IOKit I2C for DDC commands per display.
public actor DDCActor: MonitorControlling {
    public init() {}

    public func setBrightness(_ value: Int, displayID: UInt32) async throws {
        // TODO: IOKit I2C DDC/CI VCP code 0x10
    }

    public func setContrast(_ value: Int, displayID: UInt32) async throws {
        // TODO: IOKit I2C DDC/CI VCP code 0x12
    }

    public func setColorTemperature(_ kelvin: Int, displayID: UInt32) async throws {
        // TODO: IOKit I2C DDC/CI VCP code 0x0C
    }

    public func getBrightness(displayID: UInt32) async throws -> Int {
        return 72 // Placeholder
    }

    public func getContrast(displayID: UInt32) async throws -> Int {
        return 65 // Placeholder
    }
}

/// Placeholder for hardware detection — superseded by DisplayDetector.
public struct HardwareDetector: DeviceDiscovering, Sendable {
    public init() {}

    public func connectedDisplays() async throws -> [DisplayInfo] {
        let real = DisplayDetector()
        return try await real.connectedDisplays()
    }
}
