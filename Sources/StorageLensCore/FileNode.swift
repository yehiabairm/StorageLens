import Foundation

/// One folder or file in the scanned tree.
/// Files smaller than the scanner's `minNodeSize` are folded into one
/// "aggregate" node per folder, so the tree stays small in memory.
public final class FileNode: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let isAggregate: Bool
    public let lastAccess: Date?
    public let lastModified: Date?
    public internal(set) var size: Int64
    public internal(set) var fileCount: Int
    public internal(set) var children: [FileNode] = []
    public internal(set) weak var parent: FileNode?
    /// True when the scanner did not go into this folder (for example a cloud drive).
    public internal(set) var skipped = false

    public init(name: String, url: URL, isDirectory: Bool, isAggregate: Bool = false,
                size: Int64 = 0, fileCount: Int = 0,
                lastAccess: Date? = nil, lastModified: Date? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
        self.size = size
        self.fileCount = fileCount
        self.lastAccess = lastAccess
        self.lastModified = lastModified
    }

    public var path: String { url.path }

    public var sortedChildren: [FileNode] { children.sorted { $0.size > $1.size } }

    /// The newest of access and modification date.
    public var lastUsed: Date? { [lastAccess, lastModified].compactMap { $0 }.max() }

    /// Nodes from the root down to this node.
    public var pathFromRoot: [FileNode] {
        var chain: [FileNode] = [self]
        var p = parent
        while let n = p { chain.insert(n, at: 0); p = n.parent }
        return chain
    }

    func attach(_ children: [FileNode]) {
        self.children = children
        for c in children { c.parent = self }
    }

    /// Finds the node for an absolute path below (or equal to) this node.
    public func find(path target: String) -> FileNode? {
        let target = FileNode.normalize(target)
        let base = FileNode.normalize(path)
        if target == base { return self }
        let prefix = base == "/" ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        var node = self
        for comp in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children.first(where: { !$0.isAggregate && $0.name == comp }) else { return nil }
            node = next
        }
        return node
    }

    /// Removes this node and subtracts its size from every ancestor.
    public func removeFromParent() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        var a: FileNode? = p
        while let n = a {
            n.size -= size
            n.fileCount -= fileCount
            a = n.parent
        }
        parent = nil
    }

    static func normalize(_ p: String) -> String {
        var s = p
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
