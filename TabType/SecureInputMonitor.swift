import Foundation
import IOKit
import AppKit
import UserNotifications

/// Secure Input（系统反键盘监听机制）占用检测（设计 §二.8）。
/// 被占期间系统对全部 CGEventTap 屏蔽键盘事件——app 活着但收不到任何按键，
/// 日志无线索（2026-09-02 Dia 持有 2 天 17 小时实证）。无法免疫，只能检测+告知。
final class SecureInputMonitor {
    /// 卡死占用告警触发（菜单栏图标置 🔒）
    var onStuck: (() -> Void)?
    /// 占用释放且此前报过警（菜单栏图标复原）
    var onRelease: (() -> Void)?

    private var timer: DispatchSourceTimer?
    private var holderPID: pid_t?
    private var holderSince: Date?
    private var holderAppName = ""
    private var reported = false

    /// 同一 pid 连续占用超过该秒数判卡死；0 禁用监控。动态读便于实机调参
    private var threshold: TimeInterval {
        TimeInterval(UserDefaults.standard.double(forKey: "secureInputStuckSeconds"))
    }
    private let defaultThreshold: TimeInterval = 300
    private let pollInterval: TimeInterval = 15

    func start() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.activate()
        if UserDefaults.standard.object(forKey: "secureInputStuckSeconds") == nil {
            UserDefaults.standard.set(defaultThreshold, forKey: "secureInputStuckSeconds")
        }
        DebugLog.shared.log("secureInput: 监控已启动（轮询 \(Int(pollInterval))s，阈值 \(Int(threshold))s）")

        // 通知授权被拒时静默降级为仅日志通道，监控不受影响
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    private func poll() {
        let pid = Self.currentSecureInputPID()
        if let pid {
            if pid != holderPID {
                closeCycleIfAny()
                holderPID = pid
                holderSince = Date()
                reported = false
                holderAppName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
                DebugLog.shared.verbose("secureInput: 占用开始 pid=\(pid) app=\(holderAppName)")
            } else if !reported, let since = holderSince,
                      Date().timeIntervalSince(since) >= threshold {
                reported = true
                let held = Int(Date().timeIntervalSince(since))
                DebugLog.shared.log("secureInput: 卡死占用告警 pid=\(pid) app=\(holderAppName) 已持续 \(held)s——键盘事件被系统屏蔽，TabType 失明中")
                notify(
                    title: "TabType 暂时失效",
                    body: "\(holderAppName) 长时间持有安全输入（Secure Input）未释放，键盘事件被系统屏蔽。重启 \(holderAppName) 即可恢复。"
                )
                onStuck?()
            }
        } else {
            closeCycleIfAny()
        }
    }

    /// 占用结束（释放或换持有者）：报过警的周期记恢复 + 复原图标
    private func closeCycleIfAny() {
        guard let old = holderPID else { return }
        if reported {
            DebugLog.shared.log("secureInput: 已释放（pid=\(old) app=\(holderAppName)）——键盘事件恢复")
            notify(title: "TabType 已恢复", body: "安全输入（Secure Input）占用已释放，无需处理。")
            onRelease?()
        } else {
            DebugLog.shared.verbose("secureInput: 占用释放 pid=\(old)（短暂占用，正常）")
        }
        holderPID = nil
        holderSince = nil
        reported = false
        holderAppName = ""
    }

    /// 注册表根 → IOConsoleUsers → 当前会话的 kCGSSessionSecureInputPID；无占用返回 nil。
    /// 属性挂在注册表根节点上（Apple Silicon 实测，不在 IOHIDSystem）；无占用时键不存在
    private static func currentSecureInputPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else {
            return nil
        }
        for user in users where user["kCGSSessionOnConsoleKey"] as? Bool == true {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int, pid > 0 {
                return pid_t(pid)
            }
        }
        return nil
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
