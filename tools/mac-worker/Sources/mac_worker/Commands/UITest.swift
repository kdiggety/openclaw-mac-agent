import Foundation
import ArgumentParser

struct UITest: ParsableCommand {
    @Flag(help: "Emit JSON output") var json = false
    @Option(help: "Execution mode") var mode: String?
    @Option(help: "Job identifier") var jobId: String?
    @Option(help: "Project profile") var projectProfile: String?
    @Option(help: "Project root") var projectRoot: String?
    @Option(help: "Scheme") var scheme: String?
    @Option(help: "Workspace path") var workspace: String?
    @Option(help: "Project path") var project: String?
    @Option(help: "Simulator name") var simulator: String?
    @Option(help: "Result bundle path") var resultBundle: String?

    func run() throws {
        try StubResponse.printNotImplemented(command: "ui-test", json: json)
    }
}
