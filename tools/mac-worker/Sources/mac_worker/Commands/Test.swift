import Foundation
import ArgumentParser

struct Test: ParsableCommand {
    @Flag(help: "Emit JSON output") var json = false
    @Option(help: "Execution mode") var mode: String?
    @Option(help: "Job identifier") var jobId: String?
    @Option(help: "Project profile") var projectProfile: String?
    @Option(help: "Project root") var projectRoot: String?
    @Option(help: "Scheme") var scheme: String?
    @Option(help: "Workspace path") var workspace: String?
    @Option(help: "Project path") var project: String?
    @Option(help: "Destination") var destination: String?
    @Option(help: "Result bundle path") var resultBundle: String?

    func run() throws {
        try StubResponse.printNotImplemented(command: "test", json: json)
    }
}
