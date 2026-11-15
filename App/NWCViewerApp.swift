import SwiftUI
import UniformTypeIdentifiers

@main
struct NWCViewerApp: App {
    @StateObject private var model = ViewerModel()
    var body: some Scene {
        Window("NWC Viewer", id: "viewer") {
            ContentView(model: model)
                .frame(minWidth: 680, minHeight: 500)
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1000, height: 800)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", action: model.chooseFile).keyboardShortcut("o").disabled(model.busy || model.exporting)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { model.printScore(export: false) }
                    .keyboardShortcut("p").disabled(!model.ready || model.exporting)
                Button("Save PDF…") { model.printScore(export: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!model.ready || model.exporting)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model.changeZoom(0.1) }.keyboardShortcut("+").disabled(!model.ready || model.exporting)
                Button("Zoom Out") { model.changeZoom(-0.1) }.keyboardShortcut("-").disabled(!model.ready || model.exporting)
                Button("Actual Size") { model.setZoom(1) }.keyboardShortcut("0").disabled(!model.ready || model.exporting)
                Button("Fit Width", action: model.fitWidth).disabled(!model.ready || model.exporting)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: ViewerModel
    @State private var dropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ScoreWebView(model: model)
                    .opacity(model.hasScore && !model.busy ? 1 : 0)
                    .accessibilityHidden(!model.hasScore || model.busy)
                if model.busy {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Opening your score…").font(.headline)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                } else if !model.hasScore {
                    VStack(spacing: 18) {
                        if let icon = NSImage(named: "AppIcon") {
                            Image(nsImage: icon).resizable().frame(width: 96, height: 96).accessibilityHidden(true)
                        }
                        Text("Your sheet music, ready to read").font(.title2).fontWeight(.semibold)
                        Text("Open a NoteWorthy Composer score to read, print, or save as PDF.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Open NWC File…", action: model.chooseFile)
                            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                        Text("Or drop an .nwc file here").foregroundStyle(.secondary)
                        Text("Works offline · Supports NWC 1.30–2.1").font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                }
                if dropTarget { RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 3).padding(8).allowsHitTesting(false) }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.busy else { return false }
            model.open(url); return true
        } isTargeted: { dropTarget = $0 }
        .navigationTitle(model.title)
        .navigationSubtitle(model.exporting
            ? NSLocalizedString("Preparing PDF…", comment: "Export status")
            : model.hasScore ? String.localizedStringWithFormat(NSLocalizedString("page_count", comment: "Page count"), model.pageCount) : "")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: model.chooseFile) { Label("Open…", systemImage: "folder") }
                    .labelStyle(.iconOnly).help("Open NWC File…").disabled(model.busy || model.exporting)
            }
            ToolbarItemGroup(placement: .principal) {
                Button { model.changeZoom(-0.1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                    .labelStyle(.iconOnly).help("Zoom out").disabled(!model.ready || model.exporting || model.zoom <= 0.5)
                Menu {
                    Button("Fit Width", action: model.fitWidth)
                    Button("Actual Size") { model.setZoom(1) }
                    Divider()
                    ForEach([50, 75, 100, 125, 150, 200], id: \.self) { percent in
                        Button { model.setZoom(Double(percent) / 100) } label: { Text(verbatim: "\(percent)%") }
                    }
                } label: {
                    Text(verbatim: "\(Int((model.zoom * 100).rounded()))%")
                        .monospacedDigit().frame(minWidth: 40)
                }
                .menuStyle(.borderlessButton).fixedSize().help("Zoom")
                .disabled(!model.ready || model.exporting)
                Button { model.changeZoom(0.1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                    .labelStyle(.iconOnly).help("Zoom in").disabled(!model.ready || model.exporting || model.zoom >= 2)
                Button(action: model.fitWidth) { Label("Fit Width", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .labelStyle(.iconOnly).help("Fit the page to the window").disabled(!model.ready || model.exporting)
            }
            ToolbarItemGroup(placement: .automatic) {
                Button { model.printScore(export: false) } label: { Label("Print…", systemImage: "printer") }
                    .labelStyle(.iconOnly).help("Print…").disabled(!model.ready || model.exporting)
                Button { model.printScore(export: true) } label: { Label("Save PDF…", systemImage: "arrow.down.document") }
                    .labelStyle(.iconOnly).help("Save PDF…").disabled(!model.ready || model.exporting)
            }
        }
        .alert("Unable to open or export score", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
