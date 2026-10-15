import Foundation

public struct VolumeInfo: Sendable {
    public let name: String
    public let total: Int64
    /// Free space right now.
    public let available: Int64
    /// Free space plus what macOS can purge (iCloud copies, caches, snapshots).
    public let availableForImportant: Int64

    public var used: Int64 { total - available }
    public var purgeable: Int64 { max(availableForImportant - available, 0) }

    public static func current(for url: URL = URL(fileURLWithPath: "/")) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity else { return nil }
        let avail = Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeInfo(name: v.volumeName ?? "Disk", total: Int64(total), available: avail,
                          availableForImportant: v.volumeAvailableCapacityForImportantUsage ?? avail)
    }
}

public enum Permissions {
    /// True when the app can read a file that only Full Disk Access unlocks.
    public static var hasFullDiskAccess: Bool {
        let probe = "/Library/Application Support/com.apple.TCC/TCC.db"
        if let h = FileHandle(forReadingAtPath: probe) { try? h.close(); return true }
        let safari = NSHomeDirectory() + "/Library/Safari"
        return (try? FileManager.default.contentsOfDirectory(atPath: safari)) != nil
    }
}

public enum Bytes {
    public static func string(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
