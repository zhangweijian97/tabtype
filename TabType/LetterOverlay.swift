import AppKit

/// 字母标注层：徽章直接覆盖在每个应用图标上（方角、白边框、黑底、白字），
/// 覆盖窗口与切换器同 frame（画在切换器内部）。
/// 原版实测形态（2026-08-19 用户对照原版描述）：无扩展条，徽章叠于图标上。
final class LetterOverlay {
    private var window: NSWindow?
    private var view: OverlayView?

    struct Item {
        let letter: String
        let center: CGPoint  // 图标几何中心（屏幕坐标）
    }

    func show(items: [Item], switcherFrame: NSRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let v = self.view ?? OverlayView()
            self.view = v
            if self.window == nil {
                let w = NSWindow(
                    contentRect: .zero,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                w.isOpaque = false
                w.backgroundColor = .clear
                w.level = NSWindow.Level(rawValue: 1000)  // 切换器 level>35（实测被盖）；此前1000失败真因是定位bug非层级
                w.ignoresMouseEvents = true
                w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                w.hasShadow = false
                w.contentView = v
                self.window = w
            }
            v.update(items: items)
            self.window?.setFrame(switcherFrame, display: true)
            self.window?.orderFrontRegardless()
            let w = self.window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
                let mine = onScreen.filter { ($0[kCGWindowOwnerName as String] as? String) == "TabType" }
                let mineDesc = mine.map { w2 -> String in
                    let layer = w2[kCGWindowLayer as String] as? Int ?? -1
                    let b = w2[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    return "layer=\(layer) bounds=\(b)"
                }
                DebugLog.shared.log("overlay窗口自检: exists=\(w != nil) frame=\(w.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "nil") level=\(w?.level.rawValue ?? -1) visible=\(w?.isVisible ?? false) onScreenEntries=\(mine.count) \(mineDesc.joined(separator: " | "))")
            }
        }
    }

    /// 用户校准：⌘Tab 按住期间 ↑↓ 微调徽章 y（每步 8pt，持久化）
    func nudge(_ steps: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let v = self?.view else { return }
            v.badgeDY += CGFloat(steps) * 8
            DebugLog.shared.log("badgeDY 校准: \(v.badgeDY)")
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.orderOut(nil)
        }
    }
}

private final class OverlayView: NSView {
    private var items: [LetterOverlay.Item] = []
    // 用户实时校准的额外 y 偏移（↑↓ 调节，持久化 UserDefaults）
    var badgeDY: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "badgeDY")) }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: "badgeDY")
            needsDisplay = true
        }
    }

    func update(items newItems: [LetterOverlay.Item]) {
        items = newItems
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DebugLog.shared.log("overlay绘制: items=\(items.count) bounds=\(Int(bounds.width))x\(Int(bounds.height))")
        guard let winOrigin = self.window?.frame.origin else { return }
        let font = NSFont.systemFont(ofSize: 20, weight: .bold)
        for item in items {
            let local = NSPoint(x: item.center.x - winOrigin.x, y: item.center.y - winOrigin.y)
            guard local.x >= 0, local.x <= bounds.width else { continue }
            let s = NSAttributedString(string: item.letter, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ])
            let size = s.size()
            // 方形徽章：黑底、白边框、白字；badgeDY 为用户校准偏移
            let badge = NSRect(
                x: local.x - size.width / 2 - 10,
                y: local.y + badgeDY - size.height / 2 - 6,
                width: size.width + 20,
                height: size.height + 12
            )
            NSColor.black.withAlphaComponent(0.85).setFill()
            let bg = NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8)
            bg.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(roundedRect: badge, xRadius: 8, yRadius: 8)
            border.lineWidth = 2
            border.stroke()
            s.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
        }
    }
}
