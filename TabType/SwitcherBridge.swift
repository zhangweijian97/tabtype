import AppKit
import ApplicationServices

/// AX 操纵系统原生 ⌘Tab 切换器（Dock 渲染的 AXList / subrole AXProcessSwitcherList）。
/// 语义见 设计/系统设计.md §二.1b。v0.2.0 探针版：结构 dump + 选中项读写试验。
final class SwitcherBridge {
    private let overlay = LetterOverlay()

    /// 切换器条目快照——三个数组必须长度一致、同步可见。
    /// 竞态修复（2026-08-24 崩溃实证）：loadItems 后台逐字段写、jump 主线程读，
    /// 分立数组会出现「titles 已新、launchDates 未写完」窗口，jump 用 titles 的
    /// offset 索引 launchDates 越界（Swift runtime failure: Index out of range）。
    /// 捆成不可变快照 + 锁内原子替换，读方持一致快照。
    private struct Snapshot {
        let titles: [String]
        let elements: [AXUIElement]
        let launchDates: [Date]
        static let empty = Snapshot(titles: [], elements: [], launchDates: [])
    }
    private let snapshotLock = NSLock()
    private var snapshot: Snapshot = .empty

    private func loadSnapshot() -> Snapshot {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return snapshot
    }

    private func storeSnapshot(_ s: Snapshot) {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        snapshot = s
    }

    private var switcherElement: AXUIElement?

    // 竞态缓存：字母先到、切换器列表未就绪时暂存，activate 完成后补跳（按快了不丢）
    private var pendingLetters: [String] = []

    // 字母循环推进状态（同字母每按一次推进一个，500ms 内连续）
    private var lastLetter: String?
    private var lastIndex = 0
    private var lastPress = Date.distantPast
    private let repeatWindow: TimeInterval = 0.5

    /// ⌘Tab 触发时调用。切换器 AX 元素可能延迟出现，重试等待。
    /// 探针 v2：三路并测定位切换器在 AX 树的形态（Dock windows / 系统焦点 / 屏幕中心点取）。
    func activate() {
        switcherElement = nil
        storeSnapshot(.empty)
        for round in 0..<24 {
            if let el = findSwitcher() {
                switcherElement = el
                loadItems()
                let snap = loadSnapshot()
                DebugLog.shared.log("activate: 命中 第\(round)轮命中，items=\(snap.titles.count)，pending=\(pendingLetters.count)")
                for letter in pendingLetters { jump(letter: letter) }
                pendingLetters.removeAll()
                DebugLog.shared.log("activate: selected=\(currentSelectedTitle() ?? "nil")")
                showOverlay()
                return
            }
            Thread.sleep(forTimeInterval: 0.04)
        }

        DebugLog.shared.log("activate: 未找到切换器元素（重试24轮×40ms后放弃）")
    }

    /// 字母跳转：匹配 abbr 前缀，循环推进，AX 写选中。
    func jump(letter: String) {
        let snap = loadSnapshot()
        guard !snap.titles.isEmpty else {
            pendingLetters.append(letter)
            DebugLog.shared.log("jump(\(letter)): 列表未就绪，缓存（共\(pendingLetters.count)个）")
            return
        }
        let now = Date()
        let matched = snap.titles.enumerated().filter { (_, t) in
            Pinyin.abbreviation(of: t).hasPrefix(letter) || t.lowercased().hasPrefix(letter)
        }.sorted { snap.launchDates[$0.offset] < snap.launchDates[$1.offset] }
        guard !matched.isEmpty else {
            DebugLog.shared.log("jump(\(letter)): 无匹配")
            return
        }

        var target: Int
        if letter == lastLetter, now.timeIntervalSince(lastPress) < repeatWindow {
            lastIndex = (lastIndex + 1) % matched.count
            target = matched[lastIndex].offset
        } else {
            lastIndex = 0
            target = matched[0].offset
        }
        lastLetter = letter
        lastPress = now

        DebugLog.shared.log("jump(\(letter)): → \(snap.titles[target])（匹配\(matched.count)个,第\(lastIndex+1)个）")
        select(index: target, in: snap)
    }

    func nudgeOverlay(_ steps: Int) {
        overlay.nudge(steps)
    }

    func deactivate() {
        overlay.hide()
        switcherElement = nil
        storeSnapshot(.empty)
        lastLetter = nil
        pendingLetters.removeAll()
    }

    // MARK: - AX 基础

    // macOS 26.5 实测：屏幕中心点取——切换器固定在屏幕中央。
    // elementAtPosition 命中的是最深层元素（常是中央图标按钮），需向上爬父链找
    // subrole=AXProcessSwitcherList（实测中心命中 AXButton title=微信 → parent=List）
    private func findSwitcher() -> AXUIElement? {
        let sw = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let screen = NSScreen.main?.frame ?? .zero
        let err = AXUIElementCopyElementAtPosition(sw, Float(screen.midX), Float(screen.midY), &element)
        guard err == .success, var cur = element else { return nil }
        for _ in 0..<6 {
            if let subrole = string(cur, kAXSubroleAttribute as CFString),
               subrole == "AXProcessSwitcherList" {
                return cur
            }
            var ref: AnyObject?
            guard AXUIElementCopyAttributeValue(cur, kAXParentAttribute as CFString, &ref) == .success,
                  let parent = ref as! AXUIElement? else { return nil }
            cur = parent
        }
        return nil
    }

    private func loadItems() {
        guard let sw = switcherElement else { return }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sw, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }
        let elements = children
        let titles = children.compactMap { string($0, kAXTitleAttribute as CFString) }
        let running = NSWorkspace.shared.runningApplications
        let dates = titles.map { title in
            running.first(where: { ($0.localizedName ?? "") == title })?.launchDate ?? .distantPast
        }
        storeSnapshot(Snapshot(titles: titles, elements: elements, launchDates: dates))
    }

    private func showOverlay() {
        guard let sw = switcherElement else { return }
        guard let swFrame = frame(of: sw) else {
            DebugLog.shared.log("overlay: 切换器 frame 读取失败")
            return
        }
        let snap = loadSnapshot()
        var items: [LetterOverlay.Item] = []
        var positionsDump = ""
        // 稳定字母分配：同首字母组内按启动时间排序（先启动=裸字母，后启动=M×2/M×3）
        // —— 不随 MRU 重排；应用退出后组内前移；新开应用按启动时间归位（用户 2026-08-19 定稿语义）
        var groups: [String: [(idx: Int, launched: Date)]] = [:]
        for i in 0..<snap.titles.count where i < snap.elements.count {
            let abbr = Pinyin.abbreviation(of: snap.titles[i])
            guard let first = abbr.first else { continue }
            groups[String(first).uppercased(), default: []].append((i, snap.launchDates[i]))
        }
        var displayFor: [Int: String] = [:]
        for (_, members) in groups {
            let ordered = members.sorted { $0.launched < $1.launched }
            for (rank, m) in ordered.enumerated() {
                let letter = String(Pinyin.abbreviation(of: snap.titles[m.idx]).first!).uppercased()
                displayFor[m.idx] = rank == 0 ? letter : "\(letter)×\(rank + 1)"
            }
        }
        for (i, el) in snap.elements.enumerated() {
            guard let pos = position(of: el) else { continue }
            guard let size = size(of: el) else { continue }
            guard let display = displayFor[i] else { continue }
            // 徽章 x=图标几何中心，y≈图形下沿（基线96 + 用户↑↓校准-80，2026-08-19 定稿）
            let badgeYOffset: CGFloat = 16
            items.append(.init(letter: display, center: CGPoint(x: pos.x + size.width / 2, y: pos.y + badgeYOffset)))
            if i < 3 { positionsDump += " [\(i)] pos=\(Int(pos.x)),\(Int(pos.y)) size=\(Int(size.width))x\(Int(size.height))" }
        }
        DebugLog.shared.log("overlay: \(items.count)/\(snap.elements.count) 项，swFrame=\(Int(swFrame.minX)),\(Int(swFrame.minY)) \(Int(swFrame.width))x\(Int(swFrame.height))\(positionsDump)")

        overlay.show(items: items, switcherFrame: swFrame)
    }

    private func size(of el: AXUIElement) -> CGSize? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &ref) == .success,
              let val = ref as! AXValue? else { return nil }
        var sz = CGSize()
        guard AXValueGetValue(val, .cgSize, &sz) else { return nil }
        return sz
    }

    private func frame(of el: AXUIElement) -> NSRect? {
        guard let pos = position(of: el) else { return nil }
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &ref) == .success,
              let val = ref as! AXValue? else { return nil }
        var size = CGSize()
        guard AXValueGetValue(val, .cgSize, &size) else { return nil }
        return NSRect(origin: pos, size: size)
    }

    private func position(of el: AXUIElement) -> CGPoint? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &ref) == .success,
              let val = ref as! AXValue? else { return nil }
        var point = CGPoint()
        guard AXValueGetValue(val, .cgPoint, &point) else { return nil }
        return point
    }

    private func currentSelectedTitle() -> String? {
        guard let sw = switcherElement else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sw, kAXSelectedChildrenAttribute as CFString, &ref) == .success,
              let selected = ref as? [AXUIElement], let first = selected.first
        else { return nil }
        return string(first, kAXTitleAttribute as CFString)
    }

    private func select(index: Int, in snap: Snapshot) {
        guard index < snap.elements.count else { return }
        let value = [snap.elements[index]] as CFArray
        let err = AXUIElementSetAttributeValue(switcherElement!, kAXSelectedChildrenAttribute as CFString, value)
        DebugLog.shared.log("select: AXError=\(err.rawValue) 回读selected=\(currentSelectedTitle() ?? "nil")")
    }

    private func string(_ element: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr, &ref) == .success, let s = ref as? String else {
            return nil
        }
        return s
    }
}
