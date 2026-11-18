import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = TriggerEngine()
    let bridge = SwitcherBridge()
    private var statusItem: NSStatusItem?
    private var axTrusted = true
    private let secureInput = SecureInputMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        axTrusted = trusted
        TriggerEngine.debugLog.log("启动: pid=\(ProcessInfo.processInfo.processIdentifier) AXTrusted=\(trusted)")
        if !trusted {
            statusItem?.button?.title = "⚠︎"
        }
        if !engine.start() {
            TriggerEngine.debugLog.log("启动: event tap 创建失败（权限未授予）——功能不可用")
            return
        }

        secureInput.onStuck = { [weak self] in
            self?.statusItem?.button?.title = "🔒"
        }
        secureInput.onRelease = { [weak self] in
            self?.statusItem?.button?.title = (self?.axTrusted ?? true) ? "⌘" : "⚠︎"
        }
        secureInput.start()

        // activate 带重试轮询，异步派发——不能阻塞 tap 回调（Tab 事件需立即透传，
        // 否则系统切换器不弹出，AX 查找永等不到目标）
        engine.onSwitcherActivate = { [weak self] in
            guard let self else { return }
            let cmdHeld = { [weak self] in self?.engine.isCmdHeld ?? false }
            DispatchQueue.global(qos: .userInteractive).async {
                self.bridge.activate(shouldContinue: cmdHeld)
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

        // 说明拆成三行短句：单行长句会把整个菜单撑到 700pt 宽（2026-11-18 用户反馈）
        addHint("⌘Tab 唤起切换器后，敲应用名或拼音首字母选中", to: menu)
        addHint("同字母连按切换下一个；松开 ⌘ 跳到选中项", to: menu)
        addHint("按住 fn 豁免拦截（走系统原生切换）", to: menu)
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

    /// 菜单说明行：小字号、灰显（不抢菜单宽度）
    private func addHint(_ text: String, to menu: NSMenu) {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        menu.addItem(item)
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
