import Foundation

public struct TrashRecord: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public let originalPath: String
    public let trashedPath: String
    public let size: Int64
    public let date: Date
    public var restored = false
}

public enum TrashError: LocalizedError {
    case denied(String)
    case missingInTrash
    case destinationExists

    public var errorDescription: String? {
        switch self {
        case .denied(let r): return "Blocked by safety rules: \(r)"
        case .missingInTrash: return "The item is no longer in Trash."
        case .destinationExists: return "Something already exists at the original location."
        }
    }
}

/// Moves items to the Trash (never removes them), and puts them back.
public enum TrashService {
    public static func moveToTrash(_ url: URL, size: Int64, policy: SafetyPolicy = SafetyPolicy()) throws -> TrashRecord {
        if case .denied(let reason) = policy.verdict(for: url.path) { throw TrashError.denied(reason) }
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return TrashRecord(originalPath: url.path, trashedPath: resulting?.path ?? "", size: size, date: Date())
    }

    public static func restore(_ record: TrashRecord) throws {
        let fm = FileManager.default
        guard !record.trashedPath.isEmpty, fm.fileExists(atPath: record.trashedPath) else { throw TrashError.missingInTrash }
        guard !fm.fileExists(atPath: record.originalPath) else { throw TrashError.destinationExists }
        let parent = (record.originalPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try fm.moveItem(atPath: record.trashedPath, toPath: record.originalPath)
    }

    /// Removes duplicates and paths that sit inside another path in the list.
    public static func collapse(_ paths: [String]) -> [String] {
        let sorted = Set(paths.map(FileNode.normalize)).sorted()
        var out: [String] = []
        for p in sorted {
            if let last = out.last, p.hasPrefix(last == "/" ? "/" : last + "/") { continue }
            out.append(p)
        }
        return out
    }
}
