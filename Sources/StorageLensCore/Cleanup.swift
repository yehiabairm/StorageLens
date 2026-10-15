import Foundation

public enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case devJunk = "Developer junk"
    case caches = "App caches"
    case logs = "Logs"
    case downloads = "Old downloads"
    case bigOld = "Big & old files"
    case trash = "Trash"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .devJunk: return "hammer"
        case .caches: return "internaldrive"
        case .logs: return "doc.text"
        case .downloads: return "arrow.down.circle"
        case .bigOld: return "shippingbox"
        case .trash: return "trash"
        }
    }

    public var blurb: String {
        switch self {
        case .devJunk: return "Build output, simulators and package caches. Tools make them again when needed."
        case .caches: return "Data that apps keep to load faster. Apps make it again."
        case .logs: return "Old diagnostic logs and crash reports."
        case .downloads: return "Items in Downloads that you did not use for a long time."
        case .bigOld: return "Large files that you did not open for a long time."
        case .trash: return "Items already in Trash. Empty Trash in Finder to free this space."
        }
    }
}

public struct CleanupItem: Identifiable, Hashable, Sendable {
    public var id: String { path + "|" + category.rawValue }
    public let path: String
    public let title: String
    public let size: Int64
    public let category: CleanupCategory
    /// False when StorageLens only reports the item and a tool must clean it.
    public let actionable: Bool
    public let hint: String?
    public let lastUsed: Date?
}

public struct CleanupOptions: Sendable {
    public var bigThreshold: Int64
    public var oldDays: Int
    public var downloadsDays: Int
    public var now: Date
    public init(bigThreshold: Int64 = 500_000_000, oldDays: Int = 180, downloadsDays: Int = 30, now: Date = Date()) {
        self.bigThreshold = bigThreshold; self.oldDays = oldDays; self.downloadsDays = downloadsDays; self.now = now
    }
}

public enum CleanupFinder {
    struct Known {
        let rel: String
        let title: String
        let actionable: Bool
        let hint: String
    }

    static let devJunk: [Known] = [
        Known(rel: "Library/Developer/Xcode/DerivedData", title: "Xcode DerivedData", actionable: true, hint: "Xcode builds it again."),
        Known(rel: "Library/Developer/Xcode/Archives", title: "Xcode Archives", actionable: true, hint: "You lose old app builds and their debug symbols."),
        Known(rel: "Library/Developer/Xcode/iOS DeviceSupport", title: "iOS DeviceSupport", actionable: true, hint: "Xcode downloads it again when you connect a device."),
        Known(rel: "Library/Developer/Xcode/watchOS DeviceSupport", title: "watchOS DeviceSupport", actionable: true, hint: "Xcode downloads it again."),
        Known(rel: "Library/Developer/Xcode/tvOS DeviceSupport", title: "tvOS DeviceSupport", actionable: true, hint: "Xcode downloads it again."),
        Known(rel: "Library/Developer/CoreSimulator/Caches", title: "Simulator caches", actionable: true, hint: "The Simulator makes it again."),
        Known(rel: "Library/Developer/CoreSimulator/Devices", title: "iOS Simulators", actionable: false, hint: "Run `xcrun simctl delete unavailable` in Terminal."),
        Known(rel: "Library/Caches/Homebrew", title: "Homebrew downloads", actionable: true, hint: "Same as `brew cleanup`."),
        Known(rel: ".npm/_cacache", title: "npm cache", actionable: true, hint: "npm downloads packages again."),
        Known(rel: "Library/Caches/Yarn", title: "Yarn cache", actionable: true, hint: "Yarn downloads packages again."),
        Known(rel: "Library/pnpm/store", title: "pnpm store", actionable: true, hint: "pnpm downloads packages again."),
        Known(rel: "Library/Caches/pip", title: "pip cache", actionable: true, hint: "pip downloads packages again."),
        Known(rel: ".gradle/caches", title: "Gradle caches", actionable: true, hint: "Gradle downloads them again."),
        Known(rel: "Library/Caches/CocoaPods", title: "CocoaPods cache", actionable: true, hint: "CocoaPods downloads pods again."),
        Known(rel: ".cocoapods/repos", title: "CocoaPods spec repos", actionable: true, hint: "`pod install` clones them again."),
        Known(rel: "Library/Caches/org.swift.swiftpm", title: "SwiftPM cache", actionable: true, hint: "SwiftPM downloads packages again."),
        Known(rel: "Library/Caches/JetBrains", title: "JetBrains caches", actionable: true, hint: "The IDE indexes again."),
        Known(rel: "Library/Containers/com.docker.docker/Data", title: "Docker disk image", actionable: false, hint: "Run `docker system prune -a` in Terminal."),
    ]

    /// Finds cleanup candidates. Uses the scan tree for sizes when it covers
    /// a path; else it measures the path on disk.
    public static func findItems(home: URL, scan: ScanResult?, options: CleanupOptions = CleanupOptions()) -> [CleanupItem] {
        let homePath = FileNode.normalize(home.path)
        let fm = FileManager.default
        var items: [CleanupItem] = []
        var listed = Set<String>()

        func measure(_ path: String) -> Int64 {
            if let n = scan?.root.find(path: path) { return n.size }
            return sizeOf(URL(fileURLWithPath: path))
        }

        // Developer junk.
        for k in devJunk {
            let p = homePath + "/" + k.rel
            guard fm.fileExists(atPath: p) else { continue }
            let s = measure(p)
            guard s > 0 else { continue }
            items.append(CleanupItem(path: p, title: k.title, size: s, category: .devJunk, actionable: k.actionable, hint: k.hint, lastUsed: nil))
            listed.insert(p)
        }
        for nm in scan?.nodeModules.prefix(60) ?? [] where nm.size > 1_000_000 && !isGlobalInstall(nm.url) {
            let project = nm.url.deletingLastPathComponent().lastPathComponent
            items.append(CleanupItem(path: nm.path, title: "\(project)/node_modules", size: nm.size, category: .devJunk, actionable: true,
                                     hint: "`npm install` brings it back.", lastUsed: nm.parent?.lastUsed))
            listed.insert(nm.path)
        }

        // Caches and logs: one item per child folder.
        for (rel, cat) in [("Library/Caches", CleanupCategory.caches), ("Library/Logs", CleanupCategory.logs)] {
            let base = homePath + "/" + rel
            let children = (try? fm.contentsOfDirectory(atPath: base)) ?? []
            for c in children where !c.hasPrefix(".") {
                let p = base + "/" + c
                if listed.contains(p) { continue }
                let s = measure(p)
                guard s >= 1_000_000 else { continue }
                items.append(CleanupItem(path: p, title: c, size: s, category: cat, actionable: true,
                                         hint: cat == .caches ? "The app makes it again." : nil, lastUsed: nil))
                listed.insert(p)
            }
        }

        // Old downloads.
        let downloads = URL(fileURLWithPath: homePath + "/Downloads")
        let dlKeys: [URLResourceKey] = [.contentAccessDateKey, .contentModificationDateKey, .addedToDirectoryDateKey]
        let cutoff = options.now.addingTimeInterval(-Double(options.downloadsDays) * 86_400)
        for u in (try? fm.contentsOfDirectory(at: downloads, includingPropertiesForKeys: dlKeys, options: [.skipsHiddenFiles])) ?? [] {
            let v = try? u.resourceValues(forKeys: Set(dlKeys))
            let used = [v?.contentAccessDate, v?.contentModificationDate, v?.addedToDirectoryDate].compactMap { $0 }.max()
            guard let used, used < cutoff else { continue }
            let s = measure(u.path)
            guard s > 0 else { continue }
            items.append(CleanupItem(path: u.path, title: u.lastPathComponent, size: s, category: .downloads, actionable: true, hint: nil, lastUsed: used))
        }

        // Big and old files.
        let oldCutoff = options.now.addingTimeInterval(-Double(options.oldDays) * 86_400)
        for f in scan?.largeFiles ?? [] where f.size >= options.bigThreshold {
            guard let used = f.lastUsed, used < oldCutoff else { continue }
            if f.path.hasPrefix(homePath + "/.Trash/") { continue }
            items.append(CleanupItem(path: f.path, title: f.name, size: f.size, category: .bigOld, actionable: true, hint: nil, lastUsed: used))
        }

        // Trash (report only).
        let trash = homePath + "/.Trash"
        if (try? fm.contentsOfDirectory(atPath: trash)) != nil {
            let s = sizeOf(URL(fileURLWithPath: trash))
            if s > 0 {
                items.append(CleanupItem(path: trash, title: "Trash", size: s, category: .trash, actionable: false,
                                         hint: "Empty Trash in Finder to free this space.", lastUsed: nil))
            }
        }

        return items.sorted { $0.size > $1.size }
    }

    /// `…/lib/node_modules` is where npm, nvm and Homebrew keep globally installed tools, not project junk.
    public static func isGlobalInstall(_ nodeModules: URL) -> Bool {
        nodeModules.deletingLastPathComponent().lastPathComponent == "lib"
    }

    /// Allocated size of a file or a whole folder.
    public static func sizeOf(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        let set = Set(keys)
        guard let v = try? url.resourceValues(forKeys: set) else { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            guard let fv = try? f.resourceValues(forKeys: set), fv.isDirectory != true, fv.isSymbolicLink != true else { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }
}
