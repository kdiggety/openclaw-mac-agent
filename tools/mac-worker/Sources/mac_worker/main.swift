import Foundation
import ArgumentParser

@main
struct MacWorker: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mac_worker",
        abstract: "Thin macOS worker for build/test/validation tasks",
        subcommands: [
            Doctor.self,
            Build.self,
            Test.self,
            UITest.self,
            Launch.self,
            Screenshot.self,
            CollectLogs.self
        ]
    )
}
