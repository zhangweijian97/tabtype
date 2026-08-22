import CoreGraphics
import AppKit

/// 全局事件监听 + 切换器激活态状态机。
/// 语义见 设计/系统设计.md §二.1：⌘Tab 进入 switcherActive，字母拦截跳转，⌘ 松开系统原生切换。
final class TriggerEngine {
    static let debugLog = DebugLog.shared

    var onSwitcherActivate: (() -> Void)?          // ⌘ 按住 + Tab 按下（Tab 已透传，系统切换器弹出中）
    var onLetter: ((String) -> Void)?              // switcherActive 期间字母键（已被吞掉）
    var onCmdRelease: (() -> Void)?                // ⌘ 松开（退出切换器模式）
    var onArrow: ((Int) -> Void)?                  // switcherActive 期间 ↑↓ 方向键（+1=上/-1=下，徽章校准）

    private enum State {
        case idle
        case cmdHeld
        case switcherActive
    }
    private var state: State = .idle
    private var eventTap: CFMachPort?

    private static let cmdKeyCode: Int64 = 0x37
    private static let tabKeyCode: Int64 = 0x30
    /// 自己 post 的合成事件标记（防反馈环；当前未启用 post，保留结构）
    private static let synthMagic: Int64 = 0x434D5450

    private let tapCallback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
        let engine = Unmanaged<TriggerEngine>.fromOpaque(refcon!).takeUnretainedValue()
        return engine.handle(type: type, event: event)
    }

    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0),
            .commonModes
        )
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.debugLog.log("engine.start: tap 已创建并启用")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DebugLog.shared.log("tap 被系统禁用（\(type == .tapDisabledByTimeout ? "timeout" : "userInput")），已自愈重启——期间事件可能丢失")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.synthMagic {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .flagsChanged:
            Self.debugLog.verbose("flagsChanged keyCode=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=\(event.flags.rawValue) state=\(stateLabel)")
            return handleFlags(event)
        case .keyDown:
            Self.debugLog.verbose("keyDown keyCode=\(event.getIntegerValueField(.keyboardEventKeycode)) flags=\(event.flags.rawValue) state=\(stateLabel)")
            return handleKeyDown(event)
        default:
            return Unmanaged.passRetained(event)
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle: return "idle"
        case .cmdHeld: return "cmdHeld"
        case .switcherActive: return "switcherActive"
        }
    }

    private func handleFlags(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.cmdKeyCode else { return Unmanaged.passRetained(event) }

        if event.flags.contains(.maskCommand) {
            if state == .idle {
                state = .cmdHeld
                Self.debugLog.verbose("state: idle → cmdHeld")
            }
        } else {
            if state != .idle {
                state = .idle
                Self.debugLog.verbose("state: → idle（⌘松开）")
                onCmdRelease?()
            }
        }
        return Unmanaged.passRetained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch state {
        case .cmdHeld:
            if keyCode == Self.tabKeyCode {
                state = .switcherActive
                Self.debugLog.verbose("state: cmdHeld → switcherActive（⌘Tab）")
                onSwitcherActivate?()
                // Tab 透传：系统自己弹切换器并选中下一项
            }
            return Unmanaged.passRetained(event)

        case .switcherActive:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            // 箭头校准先行：箭头键事件自带 fn/numeric 标志（硬件特性），不能走 fn 豁免分支
            if keyCode == 126 { onArrow?(+1); return nil }   // ↑
            if keyCode == 125 { onArrow?(-1); return nil }   // ↓
            // fn 按住 → 字母豁免（纯净原生 ⌘Tab；箭头已在上行处理，不受影响）
            if event.flags.contains(.maskSecondaryFn) {
                return Unmanaged.passRetained(event)
            }
            if let letter = Self.letter(from: event) {
                Self.debugLog.verbose("letter: \(letter)（拦截）")
                onLetter?(letter)
                return nil // 吞掉
            }
            return Unmanaged.passRetained(event) // Tab-Tab 循环等照常透传

        case .idle:
            return Unmanaged.passRetained(event)
        }
    }

    private static func letter(from event: CGEvent) -> String? {
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0,
              let first = String(decoding: chars.prefix(length), as: UTF16.self).lowercased().first,
              first.isASCII, first.isLetter
        else { return nil }
        return String(first)
    }
}
