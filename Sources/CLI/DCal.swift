/* dcal CLI — Professional display calibration from the command line.
   Every GUI control has a CLI equivalent. Film professionals can script
   their display setup and integrate with existing toolchains. */

import ArgumentParser
import Domain

@main
struct DCal: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dcal",
        abstract: "Professional display calibration and control.",
        version: "0.1.0",
        subcommands: [
            Status.self,
            Set.self,
            Calibrate.self,
            Analyze.self,
            Preset.self,
            Profile.self,
        ],
        defaultSubcommand: Status.self
    )
}
