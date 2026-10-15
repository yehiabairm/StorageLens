import AppKit
import SwiftUI
import StorageLensCore

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.section) {
                Section("Dashboard") {
                    Label("Overview", systemImage: "gauge.with.dots.needle.33percent").tag(AppState.Section.overview)
                    Label("Explorer", systemImage: "square.grid.3x3.topleft.filled").tag(AppState.Section.explorer)
                }
                Section("Clean up") {
                    Label("Smart cleanup", systemImage: "sparkles").tag(AppState.Section.cleanup)
                    Label("Large & old files", systemImage: "shippingbox").tag(AppState.Section.large)
                    Label("Trash history", systemImage: "arrow.uturn.backward.circle").tag(AppState.Section.history)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                if !state.hasFullDiskAccess { FullDiskAccessBanner() }
                Group {
                    switch state.section ?? .overview {
                    case .overview: OverviewView()
                    case .explorer: ExplorerView()
                    case .cleanup: CleanupView()
                    case .large: LargeFilesView()
                    case .history: HistoryView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !state.selection.isEmpty { SelectionBar() }
            }
            .toolbar { ScanToolbar() }
        }
        .sheet(item: $state.pendingTrash) { plan in TrashConfirmSheet(plan: plan) }
        .sheet(isPresented: $state.showOnboarding) { OnboardingView().environmentObject(state) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.recheckAccess()
        }
        .alert(item: $state.report) { r in
            Alert(title: Text(r.moved == 0 ? "Nothing moved" : "Moved \(r.moved) item\(r.moved == 1 ? "" : "s") to Trash"),
                  message: Text(reportMessage(r)), dismissButton: .default(Text("OK")))
        }
        .alert("Error", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
        .task {
            if state.result == nil && !state.scanning && !state.showOnboarding { state.startScan(.home) }
            state.refreshCleanup()
        }
    }

    private func reportMessage(_ r: TrashReport) -> String {
        var s = "\(Bytes.string(r.freed)) is in Trash. Empty Trash in Finder to free the space. You can put items back from Trash history."
        if !r.failures.isEmpty { s += "\n\nFailed:\n" + r.failures.joined(separator: "\n") }
        return s
    }
}

struct ScanToolbar: ToolbarContent {
    @EnvironmentObject var state: AppState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if state.scanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(state.progress.files.formatted()) files · \(Bytes.string(state.progress.bytes))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button("Stop") { state.cancelScan() }
            } else {
                Menu {
                    Button("Home folder") { state.startScan(.home) }
                    Button("Whole disk") { state.startScan(.disk) }
                    Button("Choose folder…") { state.chooseFolder() }
                    Divider()
                    Toggle("Include iCloud and cloud drives (slow)", isOn: $state.includeCloud)
                } label: {
                    Label("Scan \(state.target.label)", systemImage: "arrow.clockwise")
                } primaryAction: {
                    state.startScan()
                }
                .help("Scan again")
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders are hidden from StorageLens").font(.headline)
                Text("Give StorageLens Full Disk Access to see Mail, Messages, app containers and Trash. Then scan again.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { state.openFullDiskAccessSettings() }
            Button("Check again") { state.hasFullDiskAccess = Permissions.hasFullDiskAccess }
        }
        .padding(12)
        .background(.orange.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct SelectionBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            Text("\(state.selection.count) selected · \(Bytes.string(state.selectionSize))")
                .monospacedDigit()
            Spacer()
            Button("Clear") { state.selection.removeAll() }
            Button(role: .destructive) {
                state.requestTrash(Array(state.selection.keys))
            } label: {
                Label("Move to Trash…", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(state.trashing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
