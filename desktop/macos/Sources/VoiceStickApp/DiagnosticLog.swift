import Foundation

/// A small, local diagnostic trace for hardware input sequencing.
///
/// macOS can discard an app's stdout/stderr when it is launched from Finder,
/// which makes `NSLog` unsuitable for investigating BLE button ordering in a
/// released app.  This trace intentionally records only state names and IDs;
/// it never records recognition text, API keys, or audio.
enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "com.voicestick.diagnostic-log")
    private static let maxBytes = 256 * 1_024

    static var fileURL: URL {
        AppConfig.configDirectory.appendingPathComponent("diagnostic.log")
    }

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            do {
                try FileManager.default.createDirectory(
                    at: AppConfig.configDirectory,
                    withIntermediateDirectories: true
                )
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attributes[.size] as? NSNumber,
                   size.intValue > maxBytes {
                    try data.write(to: fileURL, options: .atomic)
                    return
                }
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                // Diagnostic logging must never interfere with voice input.
            }
        }
    }
}
