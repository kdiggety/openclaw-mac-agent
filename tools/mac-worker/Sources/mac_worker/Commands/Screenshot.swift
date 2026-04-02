import Foundation
import ArgumentParser

struct Screenshot: ParsableCommand {
    @Flag(help: "Emit JSON output") var json = false
    @Option(help: "Execution mode") var mode: String?
    @Option(help: "Job identifier") var jobId: String?
    @Option(help: "Project profile") var projectProfile: String?
    @Option(help: "Project root") var projectRoot: String?
    @Option(help: "Output path") var out: String?

    func run() throws {
        try StubResponse.printNotImplemented(command: "screenshot", json: json)
    }
}
