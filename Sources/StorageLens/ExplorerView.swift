import SwiftUI
import StorageLensCore

enum NodeStyle {
    static let folderPalette: [Color] = [.blue, .indigo, .purple, .teal, .cyan, .mint, .pink, .orange]

    static func color(_ n: FileNode) -> Color {
        if n.isAggregate { return .gray }
        if n.isDirectory {
            let h = n.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
            return folderPalette[h % folderPalette.count]
        }
        switch n.url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi": return .red
        case "jpg", "jpeg", "png", "heic", "gif", "raw", "psd": return .yellow
        case "zip", "gz", "tar", "rar", "7z", "dmg", "pkg", "xip", "iso": return .brown
        case "mp3", "m4a", "wav", "aiff", "flac": return .pink
        case "pdf", "doc", "docx", "key", "pages", "xlsx", "pptx": return .orange
        default: return .green
        }
    }

    static func symbol(_ n: FileNode) -> String {
        if n.isAggregate { return "square.stack.3d.up" }
        if n.isDirectory { return n.url.pathExtension == "app" ? "app" : "folder.fill" }
        return "doc.fill"
    }
}

struct ExplorerView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let node = state.focusNode {
            VStack(spacing: 0) {
                Breadcrumb(node: node)
                HSplitView {
                    TreemapView(node: node)
                        .padding(8)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    ChildList(node: node)
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
                }
            }
            .id("\(node.id)-\(state.treeVersion)")
        } else if state.scanning {
            ScanningCard().padding(24).frame(maxWidth: 520)
        } else {
            ContentUnavailableView("No scan yet", systemImage: "internaldrive",
                                   description: Text("Scan your home folder to see where your space goes."))
        }
    }
}

struct Breadcrumb: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        HStack(spacing: 4) {
            Button { if let p = node.parent { state.focusPath = p.path } } label: { Image(systemName: "chevron.left") }
                .disabled(node.parent == nil)
                .keyboardShortcut(.upArrow, modifiers: .command)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(node.pathFromRoot) { n in
                        Button(n.parent == nil ? state.target.label : n.name) { state.focusPath = n.path }
                            .buttonStyle(.link)
                        if n !== node { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
            Spacer()
            Text("\(Bytes.string(node.size)) · \(node.fileCount.formatted()) files").monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct TreemapView: View {
    @EnvironmentObject var state: AppState
    let node: FileNode
    @State private var hovered: UUID?

    var body: some View {
        GeometryReader { geo in
            let items = Array(node.sortedChildren.filter { $0.size > 0 }.prefix(200))
            let rects = Treemap.squarify(items.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, child in
                    let r = rects[idx]
                    if r.width >= 2 && r.height >= 2 {
                        TreemapCell(node: child, size: r.size, total: node.size,
                                    hovered: hovered == child.id, selected: state.isSelected(child.path))
                            .frame(width: r.width - 2, height: r.height - 2)
                            .offset(x: r.minX + 1, y: r.minY + 1)
                            .onHover { inside in
                                if inside { hovered = child.id } else if hovered == child.id { hovered = nil }
                            }
                            .onTapGesture { state.open(child) }
                            .contextMenu { NodeMenu(node: child) }
                            .help("\(child.name)\n\(Bytes.string(child.size))\(child.isDirectory ? " · click to open" : "")")
                    }
                }
            }
        }
        .overlay {
            if node.children.isEmpty {
                Text(node.isDirectory ? "Empty or not readable" : "").foregroundStyle(.secondary)
            }
        }
    }
}

struct TreemapCell: View {
    let node: FileNode
    let size: CGSize
    let total: Int64
    let hovered: Bool
    let selected: Bool

    var body: some View {
        let c = NodeStyle.color(node)
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: [c.opacity(hovered ? 0.95 : 0.8), c.opacity(hovered ? 0.75 : 0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Color.red : Color.white.opacity(hovered ? 0.9 : 0.15),
                                  style: StrokeStyle(lineWidth: selected ? 3 : 1, dash: selected ? [6, 3] : []))
            )
            .overlay(alignment: .topLeading) {
                if size.width > 70 && size.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Image(systemName: NodeStyle.symbol(node)).font(.caption2)
                            Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        Text("\(Bytes.string(node.size)) · \(percent)").font(.caption2).monospacedDigit().opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
                    .padding(6)
                }
            }
    }

    private var percent: String {
        let p = Double(node.size) / Double(max(total, 1))
        return p.formatted(.percent.precision(.fractionLength(p < 0.1 ? 1 : 0)))
    }
}

struct NodeMenu: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        if node.isDirectory { Button("Open") { state.open(node) } }
        if !node.isAggregate {
            Button("Show in Finder") { state.reveal(node.path) }
            let verdict = state.policy.verdict(for: node.path)
            if verdict.isDenied {
                Text("Protected: \(verdict.reason ?? "")")
            } else {
                Button(state.isSelected(node.path) ? "Unselect" : "Select for cleanup") { state.toggle(node.path, size: node.size) }
                Divider()
                Button("Move to Trash…", role: .destructive) { state.requestTrash([node.path]) }
            }
        }
    }
}

struct ChildList: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        List {
            ForEach(node.sortedChildren) { child in
                HStack(spacing: 8) {
                    SelectBox(path: child.path, size: child.size, disabled: child.isAggregate)
                    SizeBarRow(node: child, parentSize: node.size)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { state.open(child) }
                .contextMenu { NodeMenu(node: child) }
            }
        }
        .listStyle(.inset)
    }
}

/// A check box that selects a path for Trash. Protected paths show a lock.
struct SelectBox: View {
    @EnvironmentObject var state: AppState
    let path: String
    let size: Int64
    var disabled = false

    var body: some View {
        let verdict = state.policy.verdict(for: path)
        if disabled {
            Image(systemName: "square").foregroundStyle(.quaternary)
        } else if verdict.isDenied {
            Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Protected: \(verdict.reason ?? "")")
        } else {
            Toggle("", isOn: Binding(get: { state.isSelected(path) }, set: { _ in state.toggle(path, size: size) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(verdict.reason ?? "Select for cleanup")
        }
    }
}
