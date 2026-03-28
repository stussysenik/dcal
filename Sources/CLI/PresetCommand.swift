import ArgumentParser

struct Preset: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage calibration presets.",
        subcommands: [
            PresetApply.self,
            PresetSave.self,
            PresetList.self,
        ]
    )
}

struct PresetApply: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a saved preset."
    )

    @Argument(help: "Preset name")
    var name: String

    func run() throws {
        print("Applying preset: \(name)")
    }
}

struct PresetSave: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save current settings as a preset."
    )

    @Argument(help: "Preset name")
    var name: String

    func run() throws {
        print("Saving preset: \(name)")
    }
}

struct PresetList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all saved presets."
    )

    func run() throws {
        print("Built-in presets:")
        print("  rec709    — Rec.709, D65, γ2.4")
        print("  dcip3     — DCI-P3, D63, γ2.6")
        print("  srgb      — sRGB, D65, γ2.2")
        print("  night     — Reduced brightness, warm white point")
    }
}
