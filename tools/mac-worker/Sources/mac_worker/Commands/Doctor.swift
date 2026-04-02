import Foundation
import ArgumentParser

struct DoctorData: Codable {
    let macOSVersion: String
    let xcodeVersion: String
    let developerDir: String
    let mode: String
    let projectProfile: String
    let projectRoot: String
}

struct Doctor: ParsableCommand {
    @Flag(help: "Emit JSON output") var json = false
    @Option(help: "Execution mode") var mode: String?
    @Option(help: "Job identifier") var jobId: String?
    @Option(help: "Project profile") var projectProfile: String?
    @Option(help: "Project root") var projectRoot: String?

    func run() throws {
        let start = Date()
        let resolvedJobId = jobId ?? "job-\(Int(start.timeIntervalSince1970))"
        let resolvedMode = mode ?? "dev"
        let resolvedProfile = projectProfile ?? ""
        let root = projectRoot ?? FileManager.default.currentDirectoryPath

        let xcode = try Shell.run("/usr/bin/xcodebuild", ["-version"])
        let devDir = try Shell.run("/usr/bin/xcode-select", ["-p"])
        let macOSVersion = try Shell.run("/usr/bin/sw_vers", ["-productVersion"])

        let data = DoctorData(
            macOSVersion: macOSVersion.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            xcodeVersion: xcode.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            developerDir: devDir.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: resolvedMode,
            projectProfile: resolvedProfile,
            projectRoot: root
        )

        let response = WorkerResponse(
            ok: true,
            command: "doctor",
            jobId: resolvedJobId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            durationSec: Date().timeIntervalSince(start),
            error: nil,
            artifacts: [],
            data: data
        )

        if json {
            try JSONPrinter.printResponse(response)
        } else {
            print("OK [doctor] job=\(resolvedJobId)")
        }
    }
}
