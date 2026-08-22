import AppKit

struct AppEntry {
    let app: NSRunningApplication
    let name: String
    let nameKey: String   // 小写全名（前缀匹配用）
    let abbrKey: String   // 词/音节首字母串（"微信"→wx，"Google Chrome"→gc）
}

/// 运行中应用列表 + 首字母匹配。
/// 排序语义：前台应用首位，其余字母序（设计 §二.2：MVP 不追求 MRU）。
final class AppListProvider {
    func currentApps() -> [AppEntry] {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && !$0.isTerminated
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let entries = running.map { app in
            let name = app.localizedName ?? (app.bundleIdentifier ?? "App")
            return AppEntry(
                app: app,
                name: name,
                nameKey: name.lowercased(),
                abbrKey: Pinyin.abbreviation(of: name)
            )
        }
        return entries.sorted { a, b in
            let aFront = a.app == frontmost
            let bFront = b.app == frontmost
            if aFront != bFront { return aFront }
            return a.nameKey < b.nameKey
        }
    }

    func matches(_ apps: [AppEntry], query: String) -> [AppEntry] {
        guard !query.isEmpty else { return apps }
        let q = query.lowercased()
        return apps.filter { $0.abbrKey.hasPrefix(q) || $0.nameKey.hasPrefix(q) }
    }
}

/// CFStringTransform 拼音首字母（设计 §二.2：系统 API 零依赖，多音字取常用读音）。
enum Pinyin {
    static func abbreviation(of name: String) -> String {
        let mutable = NSMutableString(string: name)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap(\.first)
            .map { String($0).lowercased() }
            .joined()
    }
}
