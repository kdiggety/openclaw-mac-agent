import Foundation

enum StubResponse {
    static func printNotImplemented(command: String, json: Bool) throws -> Never {
        let response = WorkerResponse(
            ok: false,
            command: command,
            jobId: "job-\(Int(Date().timeIntervalSince1970))",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            durationSec: 0,
            error: WorkerError(code: "not_implemented", message: "Swift implementation scaffold only; use shell worker for v1"),
            artifacts: [],
            data: EmptyData()
        )

        if json {
            try JSONPrinter.printResponse(response)
        } else {
            print("Use shell worker for v1")
        }

        Foundation.exit(1)
    }
}
