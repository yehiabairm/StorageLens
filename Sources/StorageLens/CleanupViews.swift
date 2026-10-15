import SwiftUI
import StorageLensCore

private let relative: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f
}()

struct CleanupView: View {
    @EnvironmentObject var state: AppState
    private let categories: [CleanupCategory] = [.devJunk, .caches, .logs, .downloads, .trash]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart cleanup").font(.title2.bold())
                    Text("Items that are safe to remove. Everything goes to Trash, so you can put it back.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Downloads older than", selection: $state.downloadsDays) {
                    ForEach([7, 30, 90, 180, 365], id: \.self) { Text("\($0) days").tag($0) }
                }
                .frame(width: 240)
                Button { state.refreshCleanup() } label: { Label("Find again", systemImage: "arrow.clockwise") }
                    .disabled(state.findingItems)
            }
            .padding(16)
            Divider()
            if state.cleanupItems.isEmpty && state.findingItems {
                ProgressView("Looking for junk…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(categories) { cat in
                        let items = state.cleanupItems.filter { $0.category == cat }
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { CleanupRow(item: $0) }
                            } header: {
                                CategoryHeader(category: cat, items: items)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct CategoryHeader: View {
    @EnvironmentObject var state: AppState
    let category: CleanupCategory
    let items: [CleanupItem]

    var body: some View {
        let selectable = items.filter { $0.actionable && state.canTrash($0.path) }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        HStack {
            Label(category.rawValue, systemImage: category.symbol).font(.headline)
            Text(Bytes.string(total)).monospacedDigit().foregroundStyle(.secondary)
            Text(category.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if !selectable.isEmpty {
                let allOn = selectable.allSatisfy { state.isSelected($0.path) }
                Button(allOn ? "Unselect all" : "Select all") {
                    for i in selectable {
                        if allOn { state.selection.removeValue(forKey: i.path) } else { state.selection[i.path] = i.size }
                    }
                }
                .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CleanupRow: View {
    @EnvironmentObject var state: AppState
    let item: CleanupItem

    var body: some View {
        HStack(spacing: 10) {
            if item.actionable {
                SelectBox(path: item.path, size: item.size)
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary).help("StorageLens shows this only. Use the hint to clean it.")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1).truncationMode(.middle)
                    if let d = item.lastUsed { Text("· used \(relative.localizedString(for: d, relativeTo: Date()))") }
                }
                .font(.caption).foregroundStyle(.secondary)
                if let hint = item.hint {
                    Text(.init(hint)).font(.caption).foregroundStyle(.tertiary)
                }
                if case .caution(let why) = state.policy.verdict(for: item.path) {
                    Label(why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(Bytes.string(item.size)).monospacedDigit().font(.body.weight(.medium))
            Button { state.reveal(item.path) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            if item.category == .trash {
                Button("Open Trash") { state.openTrash() }
            }
        }
        .padding(.vertical, 3)
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState
    @State private var onlyOld = false

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(state.oldDays) * 86_400)
        let min = Int64(state.bigMinMB) * 1_000_000
        let files = (state.result?.largeFiles ?? []).filter { f in
            f.size >= min && (!onlyOld || (f.lastUsed.map { $0 < cutoff } ?? true))
        }
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large & old files").font(.title2.bold())
                    Text("\(files.count) files · \(Bytes.string(files.reduce(0) { $0 + $1.size }))")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Picker("Bigger than", selection: $state.bigMinMB) {
                    ForEach([50, 100, 250, 500, 1000, 5000], id: \.self) { mb in
                        Text(Bytes.string(Int64(mb) * 1_000_000)).tag(mb)
                    }
                }
                .frame(width: 190)
                Toggle("Not used for", isOn: $onlyOld)
                Picker("", selection: $state.oldDays) {
                    ForEach([30, 90, 180, 365, 730], id: \.self) { Text("\($0) days").tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(!onlyOld)
            }
            .padding(16)
            Divider()
            if state.result == nil {
                ContentUnavailableView("No scan yet", systemImage: "shippingbox", description: Text("Scan first to find large files."))
            } else {
                Table(files) {
                    TableColumn("") { f in SelectBox(path: f.path, size: f.size) }.width(28)
                    TableColumn("Name") { f in
                        Text(f.name).lineLimit(1).truncationMode(.middle)
                            .contextMenu {
                                Button("Show in Finder") { state.reveal(f.path) }
                                Button("Move to Trash…", role: .destructive) { state.requestTrash([f.path]) }
                                    .disabled(!state.canTrash(f.path))
                            }
                    }
                    TableColumn("Size") { f in Text(Bytes.string(f.size)).monospacedDigit() }.width(90)
                    TableColumn("Last used") { f in
                        Text(f.lastUsed.map { relative.localizedString(for: $0, relativeTo: Date()) } ?? "—").foregroundStyle(.secondary)
                    }
                    .width(120)
                    TableColumn("Folder") { f in
                        HStack {
                            Text(f.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Spacer()
                            Button { state.reveal(f.path) } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash history").font(.title2.bold())
                    Text("Items StorageLens moved to Trash. Put one back while it is still in Trash.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Trash") { state.openTrash() }
                Button("Clear list") { state.clearHistory() }.disabled(state.history.isEmpty)
            }
            .padding(16)
            Divider()
            if state.history.isEmpty {
                ContentUnavailableView("Nothing moved yet", systemImage: "trash.slash")
            } else {
                List(state.history) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text((r.originalPath as NSString).lastPathComponent)
                            Text(r.originalPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(r.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Text(Bytes.string(r.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        if r.restored {
                            Label("Put back", systemImage: "checkmark").foregroundStyle(.green).frame(width: 110)
                        } else {
                            Button("Put back") { state.restore(r) }
                                .disabled(!FileManager.default.fileExists(atPath: r.trashedPath))
                                .frame(width: 110)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct TrashConfirmSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let plan: TrashPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Move \(plan.allowed.count) item\(plan.allowed.count == 1 ? "" : "s") to Trash?", systemImage: "trash")
                .font(.title2.bold())
            Text("This frees \(Bytes.string(plan.allowedSize)) after you empty Trash. Until then, you can put items back.")
                .foregroundStyle(.secondary)
            List {
                if !plan.allowed.isEmpty {
                    Section("Will move") {
                        ForEach(plan.allowed) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((e.path as NSString).lastPathComponent)
                                    Text(e.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    if case .caution(let why) = e.verdict {
                                        Label(why, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Text(Bytes.string(e.size)).monospacedDigit()
                            }
                        }
                    }
                }
                if !plan.denied.isEmpty {
                    Section("Protected — will not move") {
                        ForEach(plan.denied) { e in
                            HStack {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                Text((e.path as NSString).lastPathComponent)
                                Spacer()
                                Text(e.verdict.reason ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { state.pendingTrash = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash", role: .destructive) { state.performTrash(plan) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(plan.allowed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 600, height: 480)
    }
}
