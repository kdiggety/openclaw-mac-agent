import Foundation
import ArgumentParser

struct Launch: ParsableCommand {
    @Flag(help: "Emit JSON output") var json = false
    @Option(help: "Execution mode") var mode: String?
    @Option(help: "Job identifier") var jobId: String?
    @Option(help: "Project profile") var projectProfile: String?
    @Option(help: "Project root") var projectRoot: String?
    @Option(help: "App path") var app: String?
    @Option(help: "Bundle identifier") var bundleId: String?

    func run() throws {
        try StubResponse.printNotImplemented(command: "launch", json: json)
    }
}
