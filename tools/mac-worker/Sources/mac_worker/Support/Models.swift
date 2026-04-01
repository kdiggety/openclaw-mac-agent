import Foundation

struct WorkerError: Codable {
    let code: String
    let message: String
}

struct WorkerResponse<T: Codable>: Codable {
    let ok: Bool
    let command: String
    let jobId: String
    let timestamp: String
    let durationSec: Double
    let error: WorkerError?
    let artifacts: [String]
    let data: T
}

struct EmptyData: Codable {}

enum JSONPrinter {
    static func printResponse<T: Codable>(_ response: WorkerResponse<T>) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
