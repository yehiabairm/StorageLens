import AppKit
import SwiftUI
import StorageLensCore

struct TrashPlan: Identifiable {
    struct Entry: Identifiable {
        var id: String { path }
        let path: String
        let size: Int64
        let verdict: TrashVerdict
    }
    let id = UUID()
    let entries: [Entry]
    var allowed: [Entry] { entries.filter { !$0.verdict.isDenied } }
    var denied: [Entry] { entries.filter { $0.verdict.isDenied } }
    var allowedSize: Int64 { allowed.reduce(0) { $0 + $1.size } }
}

struct TrashReport: Identifiable {
    let id = UUID()
    let moved: Int
    let freed: Int64
    let failures: [String]
}

@MainActor
final class AppState: ObservableObject {
    enum Section: Hashable { case overview, explorer, cleanup, large, history }

    enum Target: Hashable {
        case home, disk, folder(URL)
        var url: URL {
            switch self {
            case .home: return FileManager.default.homeDirectoryForCurrentUser
            case .disk: return URL(fileURLWithPath: "/System/Volumes/Data")
            case .folder(let u): return u
            }
        }
        var label: String {
            switch self {
            case .home: return "Home folder"
            case .disk: return "Whole disk"
            case .folder(let u): return u.lastPathComponent
            }
        }
    }

    @Published var section: Section? = .overview
    @Published var target: Target = .home
    @Published var result: ScanResult?
    @Published var scanning = false
    @Published var progress = ScanProgress()
    @Published var focusPath: String?
    @Published var treeVersion = 0
    @Published var cleanupItems: [CleanupItem] = []
    @Published var findingItems = false
    /// Paths picked for Trash, with their size.
    @Published var selection: [String: Int64] = [:]
    @Published var history: [TrashRecord] = []
    @Published var volume: VolumeInfo?
    @Published var hasFullDiskAccess = Permissions.hasFullDiskAccess
    @Published var pendingTrash: TrashPlan?
    @Published var report: TrashReport?
    @Published var errorMessage: String?
    @Published var trashing = false
    @Published var showOnboarding = !UserDefaults.standard.bool(forKey: "onboardingDone")
    @Published var includeCloud = UserDefaults.standard.bool(forKey: "includeCloud") {
        didSet { UserDefaults.standard.set(includeCloud, forKey: "includeCloud") }
    }

    @Published var bigMinMB: Int = 500 { didSet { refreshCleanup() } }
    @Published var oldDays: Int = 180 { didSet { refreshCleanup() } }
    @Published var downloadsDays: Int = 30 { didSet { refreshCleanup() } }

    let policy = SafetyPolicy()
    private var scanner: DiskScanner?
    private var timer: Timer?
    private let historyKey = "trashHistory"

    init() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([TrashRecord].self, from: data) {
            history = saved
        }
        refreshVolume()
    }

    // MARK: Scan

    func startScan(_ t: Target? = nil) {
        if let t { target = t }
        guard !scanning else { return }
        let scanner = DiskScanner()
        if !includeCloud {
            let lib = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path
            scanner.skipPaths = [lib + "/Mobile Documents", lib + "/CloudStorage"]
        }
        self.scanner = scanner
        scanning = true
        progress = ScanProgress()
        let url = target.url
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.scanner else { return }
                self.progress = s.progress
            }
        }
        Task.detached(priority: .userInitiated) {
            let r = scanner.scan(url)
            await MainActor.run { self.finishScan(r) }
        }
    }

    func cancelScan() { scanner?.cancel() }

    private func finishScan(_ r: ScanResult) {
        timer?.invalidate()
        timer = nil
        scanner = nil
        scanning = false
        result = r
        focusPath = nil
        selection = [:]
        treeVersion += 1
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        refreshVolume()
        refreshCleanup()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(.folder(url)) }
    }

    func refreshVolume() { volume = VolumeInfo.current() }

    func refreshCleanup() {
        findingItems = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scan = result
        let opts = CleanupOptions(bigThreshold: Int64(bigMinMB) * 1_000_000, oldDays: oldDays, downloadsDays: downloadsDays)
        Task.detached(priority: .utility) {
            let items = CleanupFinder.findItems(home: home, scan: scan, options: opts)
            await MainActor.run {
                self.cleanupItems = items
                self.findingItems = false
            }
        }
    }

    // MARK: Explorer

    var focusNode: FileNode? {
        guard let root = result?.root else { return nil }
        if let p = focusPath, let n = root.find(path: p) { return n }
        return root
    }

    func open(_ node: FileNode) {
        guard node.isDirectory else { return }
        focusPath = node.path
        section = .explorer
    }

    // MARK: Selection

    func isSelected(_ path: String) -> Bool { selection[path] != nil }

    func toggle(_ path: String, size: Int64) {
        if selection[path] != nil { selection.removeValue(forKey: path) } else { selection[path] = size }
    }

    var selectionSize: Int64 {
        let kept = Set(TrashService.collapse(Array(selection.keys)))
        return selection.filter { kept.contains($0.key) }.reduce(0) { $0 + $1.value }
    }

    func canTrash(_ path: String) -> Bool { !policy.verdict(for: path).isDenied }

    // MARK: Trash

    func requestTrash(_ paths: [String]) {
        let entries = TrashService.collapse(paths).map { p in
            TrashPlan.Entry(path: p, size: selection[p] ?? knownSize(p), verdict: policy.verdict(for: p))
        }
        guard !entries.isEmpty else { return }
        pendingTrash = TrashPlan(entries: entries)
    }

    private func knownSize(_ p: String) -> Int64 {
        if let n = result?.root.find(path: p) { return n.size }
        if let i = cleanupItems.first(where: { $0.path == p }) { return i.size }
        return CleanupFinder.sizeOf(URL(fileURLWithPath: p))
    }

    func performTrash(_ plan: TrashPlan) {
        pendingTrash = nil
        trashing = true
        let entries = plan.allowed
        let policy = self.policy
        Task.detached(priority: .userInitiated) {
            var records: [TrashRecord] = []
            var failures: [String] = []
            for e in entries {
                do {
                    records.append(try TrashService.moveToTrash(URL(fileURLWithPath: e.path), size: e.size, policy: policy))
                } catch {
                    failures.append("\((e.path as NSString).lastPathComponent): \(error.localizedDescription)")
                }
            }
            let done = records, failed = failures
            await MainActor.run { self.applyTrashed(done, failures: failed) }
        }
    }

    private func applyTrashed(_ records: [TrashRecord], failures: [String]) {
        for r in records {
            let p = r.originalPath
            result?.root.find(path: p)?.removeFromParent()
            result?.largeFiles.removeAll { $0.path == p || $0.path.hasPrefix(p + "/") }
            cleanupItems.removeAll { $0.path == p || $0.path.hasPrefix(p + "/") }
            for key in selection.keys where key == p || key.hasPrefix(p + "/") { selection.removeValue(forKey: key) }
        }
        history.insert(contentsOf: records, at: 0)
        saveHistory()
        trashing = false
        treeVersion += 1
        refreshVolume()
        refreshCleanup()
        report = TrashReport(moved: records.count, freed: records.reduce(0) { $0 + $1.size }, failures: failures)
    }

    func restore(_ record: TrashRecord) {
        do {
            try TrashService.restore(record)
            if let i = history.firstIndex(where: { $0.id == record.id }) { history[i].restored = true }
            saveHistory()
            refreshVolume()
        } catch {
            errorMessage = "Could not put back \((record.originalPath as NSString).lastPathComponent): \(error.localizedDescription)"
        }
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(Array(history.prefix(500))) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    // MARK: Finder helpers

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func recheckAccess() {
        let now = Permissions.hasFullDiskAccess
        if now != hasFullDiskAccess { hasFullDiskAccess = now }
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// Quits and opens the app again. macOS applies a new Full Disk Access grant only to a fresh process.
    func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        showOnboarding = false
        recheckAccess()
        if result == nil && !scanning { startScan(.home) }
    }

    func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }
}
