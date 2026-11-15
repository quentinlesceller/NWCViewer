import SwiftUI
import UniformTypeIdentifiers

@main
struct NWCViewerApp: App {
    @StateObject private var model = ViewerModel()
    var body: some Scene {
        Window("NWC Viewer", id: "viewer") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 540)
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1000, height: 800)
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
            HStack {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                Text(model.title).font(.headline).lineLimit(1).help(model.title)
                Spacer()
                if model.exporting { ProgressView().controlSize(.small); Text("Preparing PDF…").foregroundStyle(.secondary) }
                if model.hasScore { Text(String.localizedStringWithFormat(NSLocalizedString("page_count", comment: "Number of score pages"), model.pageCount)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
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
        .toolbar {
            Button(action: model.chooseFile) { Label("Open…", systemImage: "folder").labelStyle(.titleAndIcon) }.disabled(model.busy || model.exporting)
            ControlGroup {
                Button { model.changeZoom(-0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out").accessibilityLabel("Zoom out").disabled(model.zoom <= 0.5)
                Button("\(Int((model.zoom * 100).rounded()))%") { model.setZoom(1) }.help("Reset to actual size")
                Button { model.changeZoom(0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in").accessibilityLabel("Zoom in").disabled(model.zoom >= 2)
            }.disabled(!model.ready || model.exporting)
            Button("Fit Width", action: model.fitWidth).disabled(!model.ready || model.exporting).help("Fit the page to the window")
            Button { model.printScore(export: false) } label: { Label("Print…", systemImage: "printer").labelStyle(.titleAndIcon) }.disabled(!model.ready || model.exporting)
            Button { model.printScore(export: true) } label: { Label("Save PDF…", systemImage: "arrow.down.document").labelStyle(.titleAndIcon) }.disabled(!model.ready || model.exporting)
        }
        .alert("Unable to open or export score", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
