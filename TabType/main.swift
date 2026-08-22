import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = TriggerEngine()
    let bridge = SwitcherBridge()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        TriggerEngine.debugLog.log("启动: pid=\(ProcessInfo.processInfo.processIdentifier) AXTrusted=\(trusted)")
        if !trusted {
            statusItem?.button?.title = "⚠︎"
        }
        if !engine.start() {
            TriggerEngine.debugLog.log("启动: event tap 创建失败（权限未授予）——功能不可用")
            return
        }

        // activate 带重试轮询，异步派发——不能阻塞 tap 回调（Tab 事件需立即透传，
        // 否则系统切换器不弹出，AX 查找永等不到目标）
        engine.onSwitcherActivate = { [weak self] in
            DispatchQueue.global(qos: .userInteractive).async {
                self?.bridge.activate()
            }
        }
        engine.onLetter = { [weak self] letter in
            DispatchQueue.main.async {
                self?.bridge.jump(letter: letter)
            }
        }
        engine.onArrow = { [weak self] steps in
            self?.bridge.nudgeOverlay(steps)
        }
        engine.onCmdRelease = { [weak self] in
            DispatchQueue.main.async {
                self?.bridge.deactivate()
            }
        }
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "⌘"
        let menu = NSMenu()

        let info = NSMenuItem(title: "⌘Tab 唤起原生切换器后，按住 ⌘ 敲应用名/拼音首字母选中；同字母多应用连按推进；松开 ⌘ 切换；按住 fn 豁免", action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let launch = NSMenuItem(title: "开机自动运行", action: #selector(toggleLaunch), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)

        let ax = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openAX), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 TabType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLaunch() {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            default:
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("TabType: 开机自启切换失败 \(error)")
        }
        setupStatusItem()
    }

    @objc private func openAX() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
