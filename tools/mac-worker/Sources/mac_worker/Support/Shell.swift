import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return ShellResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
