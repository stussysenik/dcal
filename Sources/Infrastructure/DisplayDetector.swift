/* Display Detection — CoreGraphics + IOKit display enumeration.
   Queries the system for all connected displays, reads EDID data
   for manufacturer/model identification, and reports capabilities.

   Key insight for correctness:
   - Apple displays (Studio Display, Pro Display XDR) do NOT support DDC/CI.
     They use Apple's proprietary brightness protocol via CoreBrightness.
   - Only third-party external displays support DDC/CI (via I2C over HDMI/DP).
   - Bit depth must be queried from ColorSync, not just assumed from vendor. */

import Foundation
import CoreGraphics
import IOKit
import Application

/* Well-known vendor IDs (from EDID PNP registry).
   Apple vendor ID = 0x0610 (1552 decimal). */
private let kAppleVendorID: UInt32 = 0x0610

public struct DisplayDetector: DeviceDiscovering, Sendable {
    public init() {}

    public func connectedDisplays() async throws -> [DisplayInfo] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0

        let err = CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        guard err == .success else { return [] }

        return (0..<Int(displayCount)).map { i in
            queryDisplay(id: displayIDs[i])
        }
    }

    private func queryDisplay(id: CGDirectDisplayID) -> DisplayInfo {
        let width = CGDisplayPixelsWide(id)
        let height = CGDisplayPixelsHigh(id)
        let mode = CGDisplayCopyDisplayMode(id)
        let pixelWidth = mode?.pixelWidth ?? width
        let pixelHeight = mode?.pixelHeight ?? height
        let isRetina = pixelWidth > width
        let isBuiltIn = CGDisplayIsBuiltin(id) != 0
        let vendorID = CGDisplayVendorNumber(id)
        let isAppleDisplay = vendorID == kAppleVendorID

        /* Control method detection:
           - Built-in displays: Apple Native (MacBook, iMac)
           - Apple external displays (Studio Display, Pro Display XDR): Apple Native
           - Third-party external displays: DDC/CI
           Apple displays use CoreBrightness, NOT DDC/CI. This is a critical
           distinction — sending DDC commands to a Studio Display does nothing. */
        let controlMethod: ControlMethod
        if isBuiltIn || isAppleDisplay {
            controlMethod = .appleNative
        } else {
            controlMethod = .ddcCI
        }

        let name = edidDisplayName(for: id) ?? "Display \(id)"
        let bitDepth = detectBitDepth(for: id)
        let colorSpace = detectColorSpace(for: id)
        let iccProfile = detectICCProfile(for: id)

        /* Estimate the panel's native EOTF gamma.
           - Apple displays (vendor 0x0610): 2.2 — Apple calibrates to sRGB/P3 transfer function.
           - OLED panels: 2.4 — closer to BT.1886 natively.
           - Generic LCD: 2.2 — industry standard for LCD panels.
           Note: this is the physical panel response, NOT the software gamma table. */
        let estimatedNativeGamma: Double
        if isAppleDisplay {
            estimatedNativeGamma = 2.2
        } else if name.lowercased().contains("oled") || colorSpace.contains("BT2020") {
            estimatedNativeGamma = 2.4
        } else {
            estimatedNativeGamma = 2.2
        }

        return DisplayInfo(
            id: id,
            name: name,
            resolution: (width: Int(pixelWidth), height: Int(pixelHeight)),
            bitDepth: bitDepth,
            controlMethod: controlMethod,
            isMain: CGDisplayIsMain(id) != 0,
            isBuiltIn: isBuiltIn,
            isRetina: isRetina,
            vendorID: vendorID,
            modelID: CGDisplayModelNumber(id),
            serialNumber: CGDisplaySerialNumber(id),
            refreshRate: mode?.refreshRate ?? 0,
            colorSpace: colorSpace,
            iccProfile: iccProfile,
            estimatedNativeGamma: estimatedNativeGamma
        )
    }

    // MARK: - Display Name Resolution

    private func edidDisplayName(for displayID: CGDirectDisplayID) -> String? {
        let targetVendor = CGDisplayVendorNumber(displayID)
        let targetModel = CGDisplayModelNumber(displayID)

        /* Try IOKit EDID name first — fastest and most accurate. */
        for className in ["IODisplayConnect", "IODisplay"] {
            var iter: io_iterator_t = 0
            guard let matching = IOServiceMatching(className) else { continue }
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iter) }

            var service = IOIteratorNext(iter)
            while service != 0 {
                defer { IOObjectRelease(service); service = IOIteratorNext(iter) }

                if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] {
                    let vendor = info[kDisplayVendorID] as? UInt32 ?? 0
                    let product = info[kDisplayProductID] as? UInt32 ?? 0

                    if vendor == targetVendor && product == targetModel,
                       let names = info[kDisplayProductName] as? [String: String],
                       let name = names.values.first {
                        return name
                    }
                }
            }
        }

        /* Fallback: system_profiler (slower but always works). */
        if let spName = systemProfilerDisplayName() {
            return spName
        }

        /* Last resort: vendor ID lookup. */
        let vendorNames: [UInt32: String] = [
            0x0610: "Apple Display",
            0x10AC: "DELL", 0x0E6D: "LG", 0x4C2D: "Samsung",
            0x22F0: "HP", 0x0469: "Acer", 0x0B49: "ASUS",
            0x3689: "BenQ", 0x2247: "Philips", 0x4A8D: "Sony",
        ]
        return vendorNames[targetVendor]
    }

    private func systemProfilerDisplayName() -> String? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPDisplaysDataType", "-detailLevel", "basic"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return nil }

            /* Parse: find lines under "Displays:" that look like display names.
               They're indented 8 spaces and end with ':'. */
            var inDisplaysSection = false
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "Displays:" {
                    inDisplaysSection = true
                    continue
                }
                if inDisplaysSection && trimmed.hasSuffix(":") && !trimmed.contains(" ") {
                    return String(trimmed.dropLast())
                }
                /* Also match multi-word names like "Studio Display:" */
                if inDisplaysSection && trimmed.hasSuffix(":") {
                    let candidate = String(trimmed.dropLast())
                    let skipPrefixes = ["Display", "Chipset", "Type", "Bus", "Total",
                                        "Vendor", "Metal", "Resolution", "Mirror",
                                        "Online", "Automatically", "Main", "Apple M",
                                        "Graphics"]
                    if !skipPrefixes.contains(where: { candidate.hasPrefix($0) }) &&
                       !candidate.isEmpty {
                        return candidate
                    }
                }
            }
        } catch {}

        return nil
    }

    // MARK: - Bit Depth Detection

    /* Bit depth detection strategy:
       1. Check IOKit EDID for NativeBitsPerColorComponent (most reliable)
       2. Check if the display is a known wide-color model (Apple P3 displays are 10-bit)
       3. Check the ColorSync profile for color depth hints
       4. Default to 8-bit (safe assumption for unknown displays) */
    private func detectBitDepth(for displayID: CGDirectDisplayID) -> Int {
        /* Strategy 1: IOKit EDID attributes */
        if let edidDepth = edidBitDepth(for: displayID) {
            return edidDepth
        }

        /* Strategy 2: Apple displays are known 10-bit P3 panels.
           Studio Display, Pro Display XDR, LG UltraFine 5K (Apple-branded)
           all have 10-bit panels with P3 color space. */
        let vendorID = CGDisplayVendorNumber(displayID)
        if vendorID == kAppleVendorID {
            return 10
        }

        /* Strategy 3: Check ColorSync profile color space.
           If the active profile uses P3 or a wide gamut, the display likely
           supports at least 10-bit. */
        let colorSpaceRef = CGDisplayCopyColorSpace(displayID)
        let csName = colorSpaceRef.name as? String ?? ""
        if csName.contains("P3") || csName.contains("Display P3") ||
           csName.contains("Wide") || csName.contains("BT2020") {
            return 10
        }

        return 8
    }

    private func edidBitDepth(for displayID: CGDirectDisplayID) -> Int? {
        var iter: io_iterator_t = 0
        guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iter) }

            if let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName))?.takeRetainedValue() as? [String: Any] {
                let vendor = info[kDisplayVendorID] as? UInt32 ?? 0
                let product = info[kDisplayProductID] as? UInt32 ?? 0

                if vendor == CGDisplayVendorNumber(displayID) &&
                   product == CGDisplayModelNumber(displayID) {
                    /* EDID stores bit depth in the display attributes dictionary. */
                    if let attrs = info["DisplayAttributes"] as? [String: Any],
                       let colorInfo = attrs["ColorCharacteristics"] as? [String: Any],
                       let depth = colorInfo["NativeBitsPerColorComponent"] as? Int {
                        return depth
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Color Space & ICC Profile Detection

    private func detectColorSpace(for displayID: CGDirectDisplayID) -> String {
        let colorSpaceRef = CGDisplayCopyColorSpace(displayID)
        let name = colorSpaceRef.name as? String ?? ""

        /* Map CoreGraphics color space names to human-readable labels. */
        if name.contains("Display P3") || name.contains("DCI-P3") { return "Display P3" }
        if name.contains("BT2020") || name.contains("Rec. 2020") { return "Rec. 2020" }
        if name.contains("Adobe") { return "Adobe RGB" }
        if name.contains("sRGB") || name.contains("IEC") { return "sRGB" }
        if name.contains("Generic RGB") { return "Generic RGB" }

        /* If no standard name, check the ICC profile description. */
        if let profileName = iccProfileDescription(from: colorSpaceRef) {
            if profileName.contains("P3") { return "Display P3" }
            if profileName.contains("sRGB") { return "sRGB" }
            if profileName.contains("Rec") { return profileName }
            /* Generic names like "Display" aren't useful — fall through. */
            if profileName.count > 8 { return profileName }
        }

        /* Apple displays (Studio Display, Pro Display XDR, etc.) use Display P3
           as their native color space. This is a documented Apple specification. */
        let vendorID = CGDisplayVendorNumber(displayID)
        if vendorID == kAppleVendorID {
            return "Display P3"
        }

        return name.isEmpty ? "sRGB" : name
    }

    /// Extract the profile description string from ICC data.
    private func iccProfileDescription(from colorSpace: CGColorSpace) -> String? {
        guard let iccData = colorSpace.copyICCData() as Data? else { return nil }
        guard iccData.count > 132 else { return nil }

        /* ICC profile structure:
           - Header: 128 bytes
           - Tag table: starts at byte 128
             - Tag count (4 bytes, big-endian UInt32)
             - Tags: 12 bytes each (signature[4] + offset[4] + size[4])
           We look for the 'desc' tag (0x64657363). */
        let tagCount = iccData.withUnsafeBytes { buf -> UInt32 in
            buf.load(fromByteOffset: 128, as: UInt32.self).bigEndian
        }

        for i in 0..<min(tagCount, 64) {
            let tagOffset = 132 + Int(i) * 12
            guard tagOffset + 12 <= iccData.count else { break }

            let sig = iccData.withUnsafeBytes { buf -> UInt32 in
                buf.load(fromByteOffset: tagOffset, as: UInt32.self).bigEndian
            }

            /* 'desc' = 0x64657363 */
            if sig == 0x64657363 {
                let dataOffset = iccData.withUnsafeBytes { buf -> UInt32 in
                    buf.load(fromByteOffset: tagOffset + 4, as: UInt32.self).bigEndian
                }
                let dataSize = iccData.withUnsafeBytes { buf -> UInt32 in
                    buf.load(fromByteOffset: tagOffset + 8, as: UInt32.self).bigEndian
                }

                let off = Int(dataOffset)
                let sz = Int(dataSize)
                guard off + sz <= iccData.count, sz > 12 else { break }

                /* The 'desc' tag type signature is at offset+0 (4 bytes),
                   reserved at offset+4 (4 bytes), string length at offset+8 (4 bytes),
                   then the ASCII string. */
                let typeSig = iccData.withUnsafeBytes { buf -> UInt32 in
                    buf.load(fromByteOffset: off, as: UInt32.self).bigEndian
                }

                /* 'desc' type = 0x64657363, 'mluc' type = 0x6D6C7563 */
                if typeSig == 0x64657363 {
                    let strLen = iccData.withUnsafeBytes { buf -> UInt32 in
                        buf.load(fromByteOffset: off + 8, as: UInt32.self).bigEndian
                    }
                    let strStart = off + 12
                    let strEnd = min(strStart + Int(strLen) - 1, iccData.count)
                    if strStart < strEnd {
                        let strData = iccData[strStart..<strEnd]
                        return String(data: strData, encoding: .ascii)?
                            .trimmingCharacters(in: .controlCharacters)
                    }
                } else if typeSig == 0x6D6C7563 {
                    /* 'mluc' (multiLocalizedUnicode) — more complex.
                       Record count at offset+8, record size at offset+12,
                       each record: language[2] + country[2] + length[4] + offset[4] */
                    let recCount = iccData.withUnsafeBytes { buf -> UInt32 in
                        buf.load(fromByteOffset: off + 8, as: UInt32.self).bigEndian
                    }
                    if recCount > 0 {
                        let recOff = off + 16 // first record starts at tag+16
                        guard recOff + 12 <= iccData.count else { break }
                        let strLength = iccData.withUnsafeBytes { buf -> UInt32 in
                            buf.load(fromByteOffset: recOff + 4, as: UInt32.self).bigEndian
                        }
                        let strOffset = iccData.withUnsafeBytes { buf -> UInt32 in
                            buf.load(fromByteOffset: recOff + 8, as: UInt32.self).bigEndian
                        }
                        let absOff = off + Int(strOffset)
                        let len = Int(strLength)
                        guard absOff + len <= iccData.count else { break }
                        let strData = iccData[absOff..<(absOff + len)]
                        /* mluc strings are UTF-16BE */
                        return String(data: strData, encoding: .utf16BigEndian)?
                            .trimmingCharacters(in: .controlCharacters)
                    }
                }

                break
            }
        }

        return nil
    }

    private func detectICCProfile(for displayID: CGDirectDisplayID) -> String {
        let colorSpaceRef = CGDisplayCopyColorSpace(displayID)

        /* Try to get the actual ICC profile description tag. */
        if let desc = iccProfileDescription(from: colorSpaceRef) {
            return desc
        }

        /* Fall back to the color space name. */
        let name = colorSpaceRef.name as? String ?? ""
        if !name.isEmpty { return name }

        return "System Default"
    }
}
