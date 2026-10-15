import Foundation

public struct ScanProgress: Sendable {
    public var files: Int
    public var bytes: Int64
    public var currentPath: String
    public init(files: Int = 0, bytes: Int64 = 0, currentPath: String = "") {
        self.files = files; self.bytes = bytes; self.currentPath = currentPath
    }
}

public struct LargeFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let lastAccess: Date?
    public let lastModified: Date?
    public var name: String { (path as NSString).lastPathComponent }
    public var folder: String { (path as NSString).deletingLastPathComponent }
    public var lastUsed: Date? { [lastAccess, lastModified].compactMap { $0 }.max() }
}

public struct ScanResult: @unchecked Sendable {
    public let target: URL
    public let root: FileNode
    public var largeFiles: [LargeFile]
    /// Top-level `node_modules` folders found during the scan.
    public let nodeModules: [FileNode]
    public let unreadable: [String]
    /// Folders not scanned on purpose (see `DiskScanner.skipPaths`).
    public let skipped: [String]
    public let duration: TimeInterval
    public let cancelled: Bool
}

/// Walks a folder tree and builds a `FileNode` tree with allocated sizes.
/// Every folder is one job on a shared queue, so deep trees (iCloud, node_modules)
/// read in parallel too. Sizes are added up bottom-up after the walk.
public final class DiskScanner: @unchecked Sendable {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentAccessDateKey, .contentModificationDateKey, .volumeIdentifierKey,
    ]
    static let keySet = Set(keys)

    /// Files at or above this size get their own node.
    public var minNodeSize: Int64 = 1_000_000
    /// Files at or above this size go into `largeFiles`.
    public var largeFileThreshold: Int64 = 50_000_000
    /// Folders read at the same time. Reads wait on disk and on cloud providers, so more than the core count helps.
    public var maxConcurrentReads = 16
    /// Folders the scanner does not go into. Cloud drives answer one folder at a time and can stall a scan.
    public var skipPaths: Set<String> = []

    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var current = ""
    private var large: [LargeFile] = []
    private var unreadable: [String] = []
    private var skipped: [String] = []
    private var cancelledFlag = false
    private var rootVolume: NSObject?

    public init() {}

    public func cancel() { sync { cancelledFlag = true } }
    public var isCancelled: Bool { sync { cancelledFlag } }
    public var progress: ScanProgress { sync { ScanProgress(files: files, bytes: bytes, currentPath: current) } }

    public func scan(_ root: URL) -> ScanResult {
        let start = Date()
        let values = try? root.resourceValues(forKeys: Self.keySet)
        rootVolume = values?.volumeIdentifier as? NSObject
        let rootNode = FileNode(name: root.path, url: root, isDirectory: true,
                                lastAccess: values?.contentAccessDate, lastModified: values?.contentModificationDate)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentReads
        queue.qualityOfService = .userInitiated
        func submit(_ dir: FileNode) {
            queue.addOperation {
                guard !self.isCancelled else { return }
                for sub in self.list(dir) { submit(sub) }
            }
        }
        submit(rootNode)
        queue.waitUntilAllOperationsAreFinished()

        var modules: [FileNode] = []
        total(rootNode, insideModules: false, modules: &modules)
        return sync {
            ScanResult(target: root, root: rootNode,
                       largeFiles: large.sorted { $0.size > $1.size },
                       nodeModules: modules.sorted { $0.size > $1.size },
                       unreadable: unreadable.sorted(),
                       skipped: skipped.sorted(),
                       duration: Date().timeIntervalSince(start),
                       cancelled: cancelledFlag)
        }
    }

    /// Reads one folder: makes file nodes, one aggregate node for small files,
    /// and empty folder nodes. Returns the folder nodes to read next.
    private func list(_ dir: FileNode) -> [FileNode] {
        let url = dir.url
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            sync { unreadable.append(url.path) }
            return []
        }
        sync { current = url.path }

        var dirNodes: [FileNode] = []
        var fileNodes: [FileNode] = []
        var bigOnes: [LargeFile] = []
        var total: Int64 = 0, count = 0
        var smallSize: Int64 = 0, smallCount = 0

        for raw in entries {
            guard let v = try? raw.resourceValues(forKeys: Self.keySet) else { continue }
            if v.isSymbolicLink == true { continue }
            // Keep child paths under the same spelling as the root (no /private/var surprises).
            let entry = url.appendingPathComponent(raw.lastPathComponent, isDirectory: v.isDirectory == true)
            if v.isDirectory == true {
                // Do not cross into other volumes (mounted disks, network shares).
                if let rv = rootVolume, let vid = v.volumeIdentifier as? NSObject, !vid.isEqual(rv) { continue }
                let sub = FileNode(name: entry.lastPathComponent, url: entry, isDirectory: true,
                                   lastAccess: v.contentAccessDate, lastModified: v.contentModificationDate)
                if skipPaths.contains(FileNode.normalize(entry.path)) {
                    sub.skipped = true
                    sync { skipped.append(entry.path) }
                    fileNodes.append(sub)
                } else {
                    dirNodes.append(sub)
                }
                continue
            }
            let s = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            total += s
            count += 1
            if s >= minNodeSize {
                fileNodes.append(FileNode(name: entry.lastPathComponent, url: entry, isDirectory: false, size: s,
                                          fileCount: 1, lastAccess: v.contentAccessDate, lastModified: v.contentModificationDate))
            } else {
                smallSize += s
                smallCount += 1
            }
            if s >= largeFileThreshold {
                bigOnes.append(LargeFile(path: entry.path, size: s, lastAccess: v.contentAccessDate, lastModified: v.contentModificationDate))
            }
        }
        sync {
            files += count
            bytes += total
            large.append(contentsOf: bigOnes)
        }

        var children = dirNodes + fileNodes
        if smallCount > 0 {
            children.append(FileNode(name: "\(smallCount) small files", url: url, isDirectory: false, isAggregate: true,
                                     size: smallSize, fileCount: smallCount))
        }
        dir.attach(children)
        return dirNodes
    }

    /// Adds sizes up from the leaves and collects top-level node_modules folders.
    private func total(_ node: FileNode, insideModules: Bool, modules: inout [FileNode]) {
        let isModules = node.name == "node_modules"
        for c in node.children where c.isDirectory {
            total(c, insideModules: insideModules || isModules, modules: &modules)
        }
        node.size = node.children.reduce(0) { $0 + $1.size }
        node.fileCount = node.children.reduce(0) { $0 + $1.fileCount }
        if isModules && !insideModules { modules.append(node) }
    }

    private func sync<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
