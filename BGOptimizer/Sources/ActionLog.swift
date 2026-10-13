import Foundation

/// Append-only text log in ~/Library/Logs/BGOptimizer, rolled over at 1 MB. Survives crashes.
final class ActionLog {
    /// ~/Library/Logs/BGOptimizer. Tests can point it elsewhere with BGOPT_LOG_DIR so they never touch your real log.
    static let dir = ProcessInfo.processInfo.environment["BGOPT_LOG_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/BGOptimizer")
    static var fileURL: URL { dir.appendingPathComponent("actions.log") }

    private let q = DispatchQueue(label: "bgopt.log")
    private let echo: Bool
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    init(echo: Bool = false) {
        self.echo = echo
        // Only you may read the log: it names the programs you run.
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.dir.path)
        for url in [Self.fileURL, Self.fileURL.appendingPathExtension("1")] where fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Block until queued lines are on disk (call before exiting).
    func flush() { q.sync {} }

    /// Delete the log history (and the rolled-over copy).
    func clear() {
        q.async {
            let fm = FileManager.default
            try? fm.removeItem(at: Self.fileURL.appendingPathExtension("1"))
            try? Data().write(to: Self.fileURL)
        }
        write("INFO", "log cleared")
    }

    /// Last `n` lines of the log, newest last.
    func tail(_ n: Int) -> String {
        flush()
        guard let text = try? String(contentsOf: Self.fileURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(n).joined(separator: "\n")
    }

    func write(_ tag: String, _ msg: String) {
        // One entry = one line: a process name or path may contain newlines or other control characters.
        let msg = String(String.UnicodeScalarView(msg.unicodeScalars.map { $0.value < 0x20 || $0.value == 0x7F ? " " : $0 }))
        q.async {
            let line = "\(self.stamp.string(from: Date()))  \(tag.padding(toLength: 8, withPad: " ", startingAt: 0)) \(msg)\n"
            if self.echo { FileHandle.standardOutput.write(Data(line.utf8)) }
            let fm = FileManager.default, url = Self.fileURL
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            if let h = try? FileHandle(forWritingTo: url) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
                try? h.close()
            }
        }
    }
}
