import ArgumentParser

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set a display parameter.",
        subcommands: [
            SetBrightness.self,
            SetContrast.self,
            SetWhitePoint.self,
            SetInput.self,
            SetVolume.self,
        ]
    )
}

struct SetBrightness: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brightness",
        abstract: "Set display brightness (0-100)."
    )

    @Argument(help: "Brightness value (0-100)")
    var value: Int

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    func run() throws {
        guard (0...100).contains(value) else {
            throw ValidationError("Brightness must be between 0 and 100.")
        }
        print("Setting brightness to \(value)" + (display.map { " on \($0)" } ?? ""))
    }
}

struct SetContrast: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contrast",
        abstract: "Set display contrast (0-100)."
    )

    @Argument(help: "Contrast value (0-100)")
    var value: Int

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    func run() throws {
        guard (0...100).contains(value) else {
            throw ValidationError("Contrast must be between 0 and 100.")
        }
        print("Setting contrast to \(value)" + (display.map { " on \($0)" } ?? ""))
    }
}

struct SetWhitePoint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "white-point",
        abstract: "Set display white point in Kelvin (e.g. 6500 for D65)."
    )

    @Argument(help: "Color temperature in Kelvin")
    var kelvin: Int

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    func run() throws {
        guard (2000...12000).contains(kelvin) else {
            throw ValidationError("Color temperature must be between 2000K and 12000K.")
        }
        print("Setting white point to \(kelvin)K" + (display.map { " on \($0)" } ?? ""))
    }
}

struct SetInput: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "input",
        abstract: "Set display input source (hdmi1, hdmi2, dp, etc.)."
    )

    @Argument(help: "Input source name")
    var source: String

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    func run() throws {
        print("Setting input to \(source)" + (display.map { " on \($0)" } ?? ""))
    }
}

struct SetVolume: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "volume",
        abstract: "Set display volume (0-100)."
    )

    @Argument(help: "Volume value (0-100)")
    var value: Int

    @Option(name: .long, help: "Target display name or ID")
    var display: String?

    func run() throws {
        guard (0...100).contains(value) else {
            throw ValidationError("Volume must be between 0 and 100.")
        }
        print("Setting volume to \(value)" + (display.map { " on \($0)" } ?? ""))
    }
}
