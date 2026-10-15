import XCTest
@testable import StorageLensCore

final class TreemapTests: XCTestCase {
    func testAreasAreProportionalAndInsideBounds() {
        let values: [Double] = [600, 300, 60, 30, 10]
        let rect = CGRect(x: 0, y: 0, width: 400, height: 250)
        let rects = Treemap.squarify(values, in: rect)
        XCTAssertEqual(rects.count, values.count)
        let total = values.reduce(0, +)
        for (v, r) in zip(values, rects) {
            XCTAssertEqual(Double(r.width * r.height), v / total * 100_000, accuracy: 1)
            XCTAssertTrue(rect.insetBy(dx: -0.01, dy: -0.01).contains(r), "\(r) is outside \(rect)")
        }
        // No two cells overlap.
        for i in rects.indices { for j in rects.indices where j > i {
            XCTAssertLessThan(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height, 0.01)
        } }
    }

    func testEmptyAndZeroInputs() {
        XCTAssertEqual(Treemap.squarify([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(Treemap.squarify([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [.zero, .zero])
    }
}

final class SafetyPolicyTests: XCTestCase {
    let p = SafetyPolicy(home: "/Users/test")

    func testDeniesCriticalPaths() {
        for path in ["/", "/Users/test", "/System/Library", "/usr/bin", "/Library/Caches",
                     "/Users/test/Documents", "/Users/test/Library", "/Users/test/Library/Caches",
                     "/Users/test/.ssh/id_rsa", "/Users/test/Library/Keychains/login.keychain-db",
                     "/Users/test/Library/Mobile Documents/x", "/Applications/Xcode.app/Contents/Info.plist",
                     "/Users/test/.Trash/old.zip"] {
            XCTAssertTrue(p.verdict(for: path).isDenied, "\(path) must be denied")
        }
    }

    func testAllowsUserData() {
        for path in ["/Users/test/Downloads/big.dmg", "/Users/test/Library/Caches/com.spotify.client",
                     "/Users/test/Library/Developer/Xcode/DerivedData", "/Users/test/code/app/node_modules",
                     "/Users/test/Library/Logs/DiagnosticReports"] {
            XCTAssertEqual(p.verdict(for: path), .allowed, path)
        }
    }

    func testPackageStoresAreAllowed() {
        XCTAssertEqual(p.verdict(for: "/Users/test/Library/pnpm/store"), .allowed)
    }

    func testGlobalNodeModulesAreNotJunk() {
        XCTAssertTrue(CleanupFinder.isGlobalInstall(URL(fileURLWithPath: "/Users/test/.npm-global/lib/node_modules")))
        XCTAssertTrue(CleanupFinder.isGlobalInstall(URL(fileURLWithPath: "/Users/test/.nvm/versions/node/v20/lib/node_modules")))
        XCTAssertFalse(CleanupFinder.isGlobalInstall(URL(fileURLWithPath: "/Users/test/code/app/node_modules")))
    }

    func testCautionCases() {
        if case .caution = p.verdict(for: "/Applications/Slack.app") {} else { XCTFail("app needs caution") }
        if case .caution = p.verdict(for: "/Users/test/Library/Application Support/Foo/cache") {} else { XCTFail("app data needs caution") }
    }

    func testTrailingSlashAndDotDot() {
        XCTAssertTrue(p.verdict(for: "/Users/test/Documents/").isDenied)
        XCTAssertTrue(p.verdict(for: "/Users/test/Downloads/../Documents").isDenied)
    }
}

final class ScannerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sl-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("a/node_modules/pkg/node_modules"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("b"), withIntermediateDirectories: true)
        try Data(count: 2_000_000).write(to: dir.appendingPathComponent("a/big.bin"))
        try Data(count: 3_000_000).write(to: dir.appendingPathComponent("a/node_modules/pkg/lib.js"))
        for i in 0..<5 { try Data(count: 1000).write(to: dir.appendingPathComponent("b/small\(i).txt")) }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testTreeSizesAndFind() throws {
        let scanner = DiskScanner()
        scanner.largeFileThreshold = 1_500_000
        let r = scanner.scan(dir)
        XCTAssertEqual(r.root.fileCount, 7)
        XCTAssertGreaterThanOrEqual(r.root.size, 5_000_000)
        let a = try XCTUnwrap(r.root.find(path: dir.appendingPathComponent("a").path))
        let b = try XCTUnwrap(r.root.find(path: dir.appendingPathComponent("b").path + "/"))
        XCTAssertEqual(a.size + b.size, r.root.size)
        // Small files fold into one aggregate node.
        XCTAssertEqual(b.children.count, 1)
        XCTAssertTrue(b.children[0].isAggregate)
        XCTAssertEqual(b.children[0].fileCount, 5)
        // Only the outer node_modules is reported.
        XCTAssertEqual(r.nodeModules.map(\.name), ["node_modules"])
        XCTAssertEqual(r.nodeModules.first?.path, dir.appendingPathComponent("a/node_modules").path)
        XCTAssertEqual(r.largeFiles.count, 2)
        XCTAssertNil(r.root.find(path: dir.path + "x/a"))
    }

    func testSkipPathsAreNotEntered() throws {
        let scanner = DiskScanner()
        scanner.skipPaths = [dir.appendingPathComponent("a").path]
        let r = scanner.scan(dir)
        let a = try XCTUnwrap(r.root.find(path: dir.appendingPathComponent("a").path))
        XCTAssertTrue(a.skipped)
        XCTAssertTrue(a.children.isEmpty)
        XCTAssertEqual(r.skipped, [dir.appendingPathComponent("a").path])
        XCTAssertTrue(r.nodeModules.isEmpty)
        XCTAssertEqual(r.root.fileCount, 5)
    }

    func testRemoveUpdatesAncestors() throws {
        let r = DiskScanner().scan(dir)
        let before = r.root.size
        let big = try XCTUnwrap(r.root.find(path: dir.appendingPathComponent("a/big.bin").path))
        let a = try XCTUnwrap(big.parent)
        let aBefore = a.size
        big.removeFromParent()
        XCTAssertEqual(r.root.size, before - big.size)
        XCTAssertEqual(a.size, aBefore - big.size)
        XCTAssertNil(r.root.find(path: big.path))
    }

    func testTrashAndRestoreRoundTrip() throws {
        let file = dir.appendingPathComponent("a/big.bin")
        let policy = SafetyPolicy(home: dir.path)
        let rec = try TrashService.moveToTrash(file, size: 2_000_000, policy: policy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rec.trashedPath))
        try TrashService.restore(rec)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testTrashRefusesDeniedPath() {
        let policy = SafetyPolicy(home: dir.path)
        XCTAssertThrowsError(try TrashService.moveToTrash(dir, size: 0, policy: policy))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testCollapse() {
        XCTAssertEqual(TrashService.collapse(["/a/b", "/a", "/a/b/c", "/ab", "/a/"]), ["/a", "/ab"])
    }
}
