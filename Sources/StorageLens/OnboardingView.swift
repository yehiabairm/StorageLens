import AppKit
import Combine
import SwiftUI
import StorageLensCore

/// First-launch guide: what the app does, how it reads the disk, the
/// permissions it needs, and the delete safety rules. Open it again from
/// Help → Welcome Guide.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var step = 0
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: HowItWorksStep()
                case 2: PermissionsStep()
                default: SafetyStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(32)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                }
                if step < lastStep {
                    Button(step == 2 && !state.hasFullDiskAccess ? "Skip for now" : "Continue") {
                        withAnimation { step += 1 }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start scanning") { state.finishOnboarding() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 640, height: 520)
        .interactiveDismissDisabled()
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.title3).foregroundStyle(.secondary)
        }
        .padding(.bottom, 18)
    }
}

private struct Point: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StepHeader(symbol: "square.grid.3x3.topleft.filled", title: "Welcome to StorageLens",
                       subtitle: "See where your disk space goes, then clean it up safely.")
            Point(symbol: "magnifyingglass", title: "Scan",
                  text: "StorageLens measures every folder in your home folder, the whole disk, or a folder you choose.")
            Point(symbol: "square.grid.3x3.topleft.filled", title: "Explore",
                  text: "A treemap shows each folder as a box. A bigger box uses more space. Click a box to go inside.")
            Point(symbol: "sparkles", title: "Clean up",
                  text: "Smart cleanup finds caches, logs, old downloads, large old files and developer junk. You pick what goes.")
        }
    }
}

private struct HowItWorksStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StepHeader(symbol: "gearshape.2", title: "How it works",
                       subtitle: "Everything happens on this Mac.")
            Point(symbol: "doc.text.magnifyingglass", title: "It reads sizes, not contents",
                  text: "The scan asks macOS for each file's size and dates. It never opens a file.")
            Point(symbol: "wifi.slash", title: "Nothing leaves your Mac",
                  text: "No network, no account, no analytics.")
            Point(symbol: "icloud.slash", title: "Cloud folders are skipped",
                  text: "iCloud Drive and Google Drive files are mostly online-only and slow to read. Turn them on in the Scan menu if you need them.")
            Point(symbol: "arrow.clockwise", title: "Scan again at any time",
                  text: "Press ⌘R to scan your home folder again, or use the Scan button in the toolbar.")
        }
    }
}

private struct PermissionsStep: View {
    @EnvironmentObject var state: AppState
    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(symbol: "lock.shield", title: "Give access to your files",
                       subtitle: "macOS hides some folders until you allow it. Without access, the scan misses them.")

            HStack(spacing: 10) {
                Image(systemName: state.hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(state.hasFullDiskAccess ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.hasFullDiskAccess ? "Full Disk Access is on" : "Full Disk Access is off").font(.headline)
                    Text(state.hasFullDiskAccess
                         ? "StorageLens can see every folder. You are ready."
                         : "Mail, Messages, app containers, Safari and Trash stay hidden.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill((state.hasFullDiskAccess ? Color.green : Color.orange).opacity(0.1)))

            if !state.hasFullDiskAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1.  Click **Open Settings**. It opens Privacy & Security → Full Disk Access.")
                    Text("2.  Turn on **StorageLens**. If it is not in the list, click **+** and pick it, or drag it in from Finder.")
                    Text("3.  If macOS asks, click **Quit & Reopen**. Else click **Restart StorageLens** below.")
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Settings") { state.openFullDiskAccessSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Show app in Finder") { state.revealApp() }
                    Button("Restart StorageLens") { state.relaunch() }
                }
            }

            Text("macOS can also ask for Desktop, Documents and Downloads the first time a scan reaches them. Click **Allow**. With Full Disk Access on, it does not ask.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(ticker) { _ in state.recheckAccess() }
    }
}

private struct SafetyStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StepHeader(symbol: "trash.slash", title: "Deleting is safe",
                       subtitle: "StorageLens never removes a file for good.")
            Point(symbol: "trash", title: "Only to Trash",
                  text: "Selected items go to Trash. You free the space when you empty Trash in Finder.")
            Point(symbol: "checklist", title: "You confirm every move",
                  text: "A sheet lists each item and its size before anything moves.")
            Point(symbol: "lock.fill", title: "Protected places",
                  text: "System folders, your standard folders, Keychains, Mail, iCloud, app containers and ~/.ssh are locked. App data shows an orange warning.")
            Point(symbol: "arrow.uturn.backward.circle", title: "Put back",
                  text: "Trash history puts any item back where it was, while it is still in Trash.")
        }
    }
}
