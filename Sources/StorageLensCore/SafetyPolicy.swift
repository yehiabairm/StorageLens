import Foundation

public enum TrashVerdict: Equatable, Sendable {
    case allowed
    case caution(String)
    case denied(String)

    public var isDenied: Bool { if case .denied = self { return true }; return false }
    public var reason: String? {
        switch self {
        case .allowed: return nil
        case .caution(let r), .denied(let r): return r
        }
    }
}

/// Decides which paths StorageLens may move to Trash.
/// The rule: deny anything that can break macOS, an app, or an account;
/// warn on app data; allow the rest.
public struct SafetyPolicy: Sendable {
    public let home: String

    static let standardHomeFolders: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
        "Applications", "Developer", "Sites",
    ]
    static let personalLibraryFolders: Set<String> = [
        "Keychains", "Mail", "Messages", "Mobile Documents", "CloudStorage", "Preferences",
        "Accounts", "Cookies", "Safari", "Calendars", "Photos", "Group Containers", "Containers",
        "Application Scripts", "IdentityServices", "Passes", "Sharing", "Suggestions",
    ]
    static let secretDotFolders: Set<String> = [".ssh", ".gnupg", ".aws", ".kube", ".config", ".docker", ".Trash"]

    public init(home: String = NSHomeDirectory()) {
        self.home = FileNode.normalize(home)
    }

    public func verdict(for rawPath: String) -> TrashVerdict {
        let path = FileNode.normalize(URL(fileURLWithPath: rawPath).standardizedFileURL.path)
        if path == "/" || path == home { return .denied("Top-level folder.") }

        let comps = path.split(separator: "/").map(String.init)
        if let appIndex = comps.firstIndex(where: { $0.hasSuffix(".app") }), appIndex < comps.count - 1 {
            return .denied("File inside an app. Remove the whole app instead.")
        }

        if path.hasPrefix(home + "/") {
            let rel = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
            if rel.count == 1 && Self.standardHomeFolders.contains(rel[0]) {
                return .denied("Standard macOS folder.")
            }
            if Self.secretDotFolders.contains(rel[0]) {
                return rel[0] == ".Trash"
                    ? .denied("Already in Trash. Empty Trash in Finder.")
                    : .denied("Holds keys or settings.")
            }
            if rel[0] == "Library" {
                if rel.count <= 2 { return .denied("Core Library folder.") }
                switch rel[1] {
                case "Caches", "Logs", "Developer", "pnpm":
                    return .allowed
                case let f where Self.personalLibraryFolders.contains(f):
                    return .denied("Holds personal, account or app-sandbox data.")
                default:
                    return .caution("App data. The app can lose settings or data.")
                }
            }
            if path.hasSuffix(".photoslibrary") { return .caution("Photos library. You lose every photo in it.") }
            return .allowed
        }

        if comps.first == "Applications" && comps.count >= 2 {
            return .caution("App. Remove it only if you do not use it.")
        }
        if comps.starts(with: ["Users", "Shared"]) && comps.count >= 3 { return .allowed }
        if comps.first == "Volumes" && comps.count >= 3 { return .allowed }
        return .denied("System location.")
    }
}
