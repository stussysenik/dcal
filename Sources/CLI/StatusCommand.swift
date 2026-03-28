import ArgumentParser
import Foundation
import Domain
import Application
import Infrastructure

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show connected displays and their current settings."
    )

    @Flag(name: .shortAndLong, help: "Show detailed information including vendor/model IDs.")
    var verbose = false

    func run() throws {
        print("dcal v0.1.0 — Display Calibration Suite")
        print("════════════════════════════════════════════════════════════")

        let detector = DisplayDetector()
        let displays = try syncBridge { try await detector.connectedDisplays() }

        if displays.isEmpty {
            print("  No displays detected.")
            return
        }

        for (index, display) in displays.enumerated() {
            let mainTag = display.isMain ? " ★ main" : ""
            let typeDesc = display.isBuiltIn ? "built-in" : "external"
            let retinaDesc = display.isRetina ? " · retina" : ""
            let res = "\(display.resolution.width)×\(display.resolution.height)"
            let hz = display.refreshRate > 0 ? " @ \(Int(display.refreshRate))Hz" : ""

            print("")
            print("  \(index + 1). \(display.name)\(mainTag)")
            print("     ┌─────────────────────────────────────────────────")
            print("     │ Resolution    \(res)\(hz)")
            print("     │ Bit Depth     \(display.bitDepth)-bit")
            print("     │ Color Space   \(display.colorSpace)")
            print("     │ ICC Profile   \(display.iccProfile)")
            print("     │ Type          \(typeDesc)\(retinaDesc)")
            print("     │ Control       \(display.controlMethod.rawValue)")

            if verbose {
                print("     │")
                print("     │ Display ID    0x\(String(display.id, radix: 16, uppercase: true))")
                print("     │ Vendor        0x\(String(display.vendorID, radix: 16, uppercase: true)) (\(display.vendorID))")
                print("     │ Model         0x\(String(display.modelID, radix: 16, uppercase: true)) (\(display.modelID))")
                if display.serialNumber != 0 {
                    print("     │ Serial        \(display.serialNumber)")
                }
            }

            print("     └─────────────────────────────────────────────────")
        }

        let controllable = displays.filter { $0.isControllable }.count
        let ddcDisplays = displays.filter { $0.controlMethod == .ddcCI }
        let appleDisplays = displays.filter { $0.controlMethod == .appleNative }

        print("")
        print("  \(displays.count) display\(displays.count == 1 ? "" : "s") detected")

        if !ddcDisplays.isEmpty {
            print("  \(ddcDisplays.count) with DDC/CI (brightness, contrast, input control)")
        }
        if !appleDisplays.isEmpty {
            print("  \(appleDisplays.count) with Apple Native control (brightness)")
        }

        print("")
        if controllable > 0 {
            print("  dcal set brightness <value>         adjust brightness")
            print("  dcal calibrate --target rec709      auto-calibrate")
        } else {
            print("  No controllable displays found.")
        }
    }
}
