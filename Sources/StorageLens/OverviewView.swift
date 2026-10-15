import SwiftUI
import StorageLensCore

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DiskCard()
                ReclaimGrid()
                if let root = state.result?.root {
                    TopFolders(root: root).id(state.treeVersion)
                } else if state.scanning {
                    ScanningCard()
                }
                if let r = state.result, !r.skipped.isEmpty {
                    Label("Skipped \(r.skipped.count) cloud folder\(r.skipped.count == 1 ? "" : "s") (iCloud Drive, Google Drive and similar). Turn on \"Include iCloud and cloud drives\" in the Scan menu to measure them.", systemImage: "icloud.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let r = state.result, !r.unreadable.isEmpty {
                    Label("\(r.unreadable.count) folders could not be read. Full Disk Access shows them.", systemImage: "eye.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }
}

struct DiskCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Card {
            if let v = state.volume {
                let scanned = state.result?.root.size ?? 0
                let other = max(v.used - scanned, 0)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.name).font(.title2.bold())
                        Spacer()
                        Text("\(Bytes.string(v.available)) free of \(Bytes.string(v.total))")
                            .font(.title3).monospacedDigit()
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let total = Double(max(v.total, 1))
                        HStack(spacing: 2) {
                            bar(Color.accentColor, Double(min(scanned, v.used)) / total * w)
                            bar(.gray.opacity(0.55), Double(other) / total * w)
                            bar(.green.opacity(0.35), Double(v.available) / total * w)
                        }
                    }
                    .frame(height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack(spacing: 18) {
                        legend(Color.accentColor, state.result == nil ? "Not scanned yet" : "\(state.target.label) · \(Bytes.string(scanned))")
                        legend(.gray.opacity(0.55), "System, apps, other users, snapshots · \(Bytes.string(other))")
                        legend(.green.opacity(0.35), "Free · \(Bytes.string(v.available))")
                    }
                    .font(.callout)
                    if v.purgeable > 0 {
                        Text("macOS can also free up to \(Bytes.string(v.purgeable)) of purgeable space (iCloud copies, local snapshots) when it needs it.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Disk information is not available.")
            }
        }
    }

    private func bar(_ c: Color, _ w: Double) -> some View {
        Rectangle().fill(c).frame(width: max(w, 0))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            Text(t).monospacedDigit()
        }
    }
}

struct ReclaimGrid: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What you can clean").font(.headline)
                if state.findingItems { ProgressView().controlSize(.small) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(CleanupCategory.allCases) { cat in
                    let items = state.cleanupItems.filter { $0.category == cat }
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    Button {
                        state.section = cat == .bigOld ? .large : .cleanup
                    } label: {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(cat.rawValue, systemImage: cat.symbol).font(.subheadline.weight(.semibold))
                                Text(Bytes.string(total)).font(.title2.bold()).monospacedDigit()
                                Text("\(items.count) item\(items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TopFolders: View {
    @EnvironmentObject var state: AppState
    let root: FileNode

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Biggest items in \(state.target.label)").font(.headline)
                    Spacer()
                    Button("Open Explorer") { state.focusPath = nil; state.section = .explorer }
                }
                ForEach(Array(root.sortedChildren.prefix(10))) { node in
                    SizeBarRow(node: node, parentSize: root.size)
                        .contentShape(Rectangle())
                        .onTapGesture { if node.isDirectory { state.open(node) } }
                }
            }
        }
    }
}

struct ScanningCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack { ProgressView().controlSize(.small); Text("Scanning \(state.target.label)…").font(.headline) }
                Text("\(state.progress.files.formatted()) files · \(Bytes.string(state.progress.bytes))").monospacedDigit()
                Text(state.progress.currentPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

struct SizeBarRow: View {
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: NodeStyle.symbol(node)).foregroundStyle(NodeStyle.color(node)).frame(width: 18)
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(node.skipped ? "not scanned" : Bytes.string(node.size)).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule().fill(NodeStyle.color(node).opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(Double(node.size) / Double(max(parentSize, 1))))
            }
            .frame(height: 4)
        }
    }
}
