import Foundation

/// 诊断日志，两级：
/// - log()：关键事件（启动/权限/tap 自愈/定位失败），默认开启——出问题足以定位
/// - verbose()：事件流（每个键/状态转换），--debug 或 UserDefaults debug=1 开启
/// 通道：~/Library/Logs/TabType.log（文件通道，unified log 对本 app 实测不可靠）
final class DebugLog {
    static let shared = DebugLog()
    private let verboseEnabled = CommandLine.arguments.contains("--debug")
        || UserDefaults.standard.bool(forKey: "debug")
    private let path = NSHomeDirectory() + "/Library/Logs/TabType.log"
    private let queue = DispatchQueue(label: "tabtype.debuglog")
    private let stamp = ISO8601DateFormatter()

    func log(_ message: String) {
        write("[info] \(message)")
    }

    func verbose(_ message: String) {
        guard verboseEnabled else { return }
        write("[verb] \(message)")
    }

    private func write(_ message: String) {
        let line = "\(stamp.string(from: Date())) \(message)\n"
        queue.async {
            if let fh = FileHandle(forWritingAtPath: self.path) {
                fh.seekToEndOfFile()
                fh.write(line.data(using: .utf8)!)
                try? fh.close()
            } else {
                try? line.write(toFile: self.path, atomically: true, encoding: .utf8)
            }
        }
    }
}
