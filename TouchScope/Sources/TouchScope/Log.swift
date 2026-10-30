import Foundation

enum Log {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("touchscope.log")

    static func reset() {
        try? Data().write(to: url)
    }

    static func write(_ line: String) {
        let stamp = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000)
        let text = String(format: "[%.3f] %@\n", stamp, line)
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
