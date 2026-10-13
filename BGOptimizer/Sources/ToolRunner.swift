import Foundation

/// Runs an outside program by its full path with fixed arguments (never through a shell), and never waits longer than
/// `timeout`. A program that hangs (for example one that waits for a desktop session that does not exist) is stopped and
/// the caller gets an empty answer instead of a frozen window.
enum ToolRunner {
    struct Result {
        var status: Int32
        var output: String
        var timedOut: Bool
    }

    private final class Box { var data = Data() }

    @discardableResult
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 10) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice          // a program that waits for input gets end-of-file, not a hang
        do { try p.run() } catch { return Result(status: -1, output: "", timedOut: false) }

        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut {            // it ignored the polite request
                kill(p.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 1)
            }
            return Result(status: -1, output: "", timedOut: true)
        }
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(data: box.data, encoding: .utf8) ?? "", timedOut: false)
    }
}
