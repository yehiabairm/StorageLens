# StorageLens

A native macOS app that shows where your disk space goes, and helps you clean it up safely.

- **Treemap + list** of every folder, sized by the space it uses. Click a box to go inside.
- **Smart cleanup** finds caches, logs, old downloads, large old files and developer junk.
- **Safe delete.** Items go to Trash only, after you confirm. You can put them back.
- **Private.** Everything runs on your Mac. No network, no account, no analytics.

## Requirements

| What | Version | Why |
|------|---------|-----|
| macOS | 14 Sonoma or later | The app uses SwiftUI APIs from macOS 14. |
| Mac | Apple silicon or Intel | The build runs on the Mac you build it on. |
| Swift toolchain | Swift 5.10 or later | Comes with **Xcode 15.3+** or the **Command Line Tools**. |
| Disk space for the build | About 200 MB | Build files in `.build/`. |

Check if you have Swift:

```bash
swift --version
```

If the command is missing, install the Command Line Tools:

```bash
xcode-select --install
```

## Install

1. Get the code:

   ```bash
   git clone https://github.com/yehiabairm/StorageLens.git
   ```

2. Build the app and copy it to `~/Applications`:

   ```bash
   cd StorageLens && zsh scripts/build-app.sh --install
   ```

3. Open it:

   ```bash
   open ~/Applications/StorageLens.app
   ```

The first launch shows a short welcome guide. It explains how the app works and helps you turn on Full Disk Access (see below).

To build without installing, leave out `--install`. The app is then in `build/StorageLens.app`.

### Why build it yourself?

The app is not signed with an Apple Developer ID, so there is no download. The build script signs it locally ("ad-hoc"). macOS trusts an app you built on your own Mac, so Gatekeeper does not block it.

### Update

```bash
cd StorageLens && git pull && zsh scripts/build-app.sh --install
```

After an update, macOS can ask for Full Disk Access again, because the local signature changes with each build.

### Uninstall

Drag `~/Applications/StorageLens.app` to Trash. To also remove its settings and Trash history:

```bash
defaults delete dev.beram.StorageLens
```

## Permissions

StorageLens needs to **read** your folders to measure them. It needs to **move items to Trash** to clean them. It does not use the network.

| Permission | Needed for | How to give it |
|------------|-----------|----------------|
| **Full Disk Access** (recommended) | Mail, Messages, Safari, app containers, Trash and other protected folders. Without it, these show as unreadable and the totals are low. | System Settings → Privacy & Security → **Full Disk Access** → turn on StorageLens. Then quit and open the app again. The welcome guide and the orange banner have a button for this. |
| **Desktop, Documents, Downloads** | Only if Full Disk Access is off. macOS asks the first time the scan reaches each folder. | Click **Allow** in the macOS prompt. |

The app is **not sandboxed**. A sandboxed app cannot measure your whole disk or move files outside its own container. This is why it is built from source and not shipped through the App Store.

You can open the guide again at any time: **Help → Welcome Guide**.

## How it works

```
Scan ──► FileNode tree ──► Overview / Explorer / Large files
  │                              │
  └──► Cleanup finder ──► Smart cleanup ──► confirm sheet ──► Trash ──► Trash history (Put back)
```

- **Scan.** Each folder is one job on a queue with 16 parallel readers. For each file, the app reads only the allocated size and the dates. It never opens a file. Files under 1 MB in a folder become one "small files" box, so memory stays low.
- **Cloud folders.** `~/Library/Mobile Documents` (iCloud Drive) and `~/Library/CloudStorage` (Google Drive, Dropbox, OneDrive) are skipped by default. Most of their files are online-only and use no local space, and they read one folder at a time, which can stall a scan. Turn them on in the Scan menu: **Include iCloud and cloud drives (slow)**.
- **Other volumes.** The scan does not cross into mounted disks or network shares.

## Views

| View | What you see |
|------|--------------|
| Overview | Disk used and free, the space the scanned folder uses, purgeable space, cleanup totals, the biggest items. |
| Explorer | A treemap plus a sorted list. Click a box to open a folder. Right-click for Show in Finder, Select, Move to Trash. |
| Smart cleanup | Developer junk (Xcode DerivedData, Archives, DeviceSupport, simulators, npm, pnpm, Yarn, pip, Gradle, CocoaPods, SwiftPM, Homebrew, project `node_modules`, Docker), app caches, logs, old downloads, Trash size. |
| Large & old files | Files over a size limit, with a "not used for N days" filter. |
| Trash history | Every item StorageLens moved. **Put back** returns it while it is still in Trash. |

## Delete safety

- StorageLens **never deletes** a file for good. It only moves items to Trash (`FileManager.trashItem`). You empty Trash yourself.
- Every move goes through a confirm sheet that lists each item and its size.
- `SafetyPolicy` **blocks**: system locations, your home folder and its standard folders, `~/Library` and its direct children, Keychains, Mail, Messages, iCloud, app containers, `~/.ssh` and other key folders, and files inside an `.app`.
- `SafetyPolicy` **warns** (orange) on app data and on apps.
- Global tool folders (`…/lib/node_modules` from npm, nvm or Homebrew) are not listed as junk.
- Simulators and Docker are report-only. The app shows the command that cleans them safely (`xcrun simctl delete unavailable`, `docker system prune -a`).

## Develop

```bash
swift build          # debug build
swift test           # core tests: scanner, treemap, safety rules, trash and put back
swift run            # run without a bundle (some permissions behave differently)
```

| Folder | Contents |
|--------|----------|
| `Sources/StorageLensCore` | Scanner, treemap layout, safety policy, cleanup finder, Trash service. No UI. |
| `Sources/StorageLens` | The SwiftUI app. |
| `Tests/StorageLensCoreTests` | Unit tests for the core. |
| `scripts/build-app.sh` | Builds, signs and (with `--install`) installs the `.app`. |
| `scripts/make-icon.swift` | Draws the app icon. |

## License

MIT. See [LICENSE](LICENSE).
