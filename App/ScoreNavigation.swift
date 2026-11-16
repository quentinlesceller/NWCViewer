import SwiftUI
import PDFKit

struct ScoreSidebar: View {
    @ObservedObject var model: ViewerModel
    var body: some View {
        VStack(spacing: 0) {
            Text("Pages").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding()
            if let document = model.thumbnailDocument {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(0..<document.pageCount, id: \.self) { index in
                                if let page = document.page(at: index) {
                                    Button { model.goToPage(index + 1) } label: {
                                        PageThumbnail(page: page, number: index + 1, selected: model.currentPage == index + 1)
                                    }.buttonStyle(.plain).id(index + 1)
                                    .accessibilityLabel(Text(String.localizedStringWithFormat(NSLocalizedString("Page %ld", comment: "Page number"), index + 1)))
                                }
                            }
                        }.padding(.horizontal, 16).padding(.bottom)
                    }
                    .onChange(of: model.currentPage) { page in proxy.scrollTo(page, anchor: .center) }
                    .onAppear { proxy.scrollTo(model.currentPage, anchor: .center) }
                }.id(ObjectIdentifier(document))
            } else if model.hasScore {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }.frame(width: 170).background(.regularMaterial)
        .onAppear { model.prepareThumbnails() }
    }
}

private struct PageThumbnail: View {
    let page: PDFPage
    let number: Int
    let selected: Bool
    @State private var image: NSImage?
    var body: some View {
        VStack(spacing: 6) {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .background(.white).overlay(Rectangle().stroke(selected ? Color.accentColor : .gray.opacity(0.35), lineWidth: selected ? 3 : 1))
            } else { ProgressView().frame(height: 150) }
            Text(verbatim: String(number)).font(.caption).foregroundStyle(selected ? Color.accentColor : .secondary)
        }
        .onAppear { if image == nil { image = page.thumbnail(of: NSSize(width: 260, height: 340), for: .mediaBox) } }
    }
}

struct ScoreLocationSheet: View {
    @ObservedObject var model: ViewerModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var value = ""
    private var number: Int? { Int(value) }
    private var valid: Bool {
        guard let number else { return false }
        return kind == 0 ? (1...max(1, model.pageCount)).contains(number) : model.measureNumbers.contains(number)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Go To…").font(.headline)
            Picker("Destination", selection: $kind) { Text("Page").tag(0); Text("Measure").tag(1) }.pickerStyle(.segmented)
            TextField(LocalizedStringKey(kind == 0 ? "Page" : "Measure"), text: $value)
                .onSubmit { navigate() }
            if kind == 0 { Text(String.localizedStringWithFormat(NSLocalizedString("Page 1–%ld", comment: "Page range"), model.pageCount)).foregroundStyle(.secondary) }
            else { Text("Enter a measure number shown in the score.").foregroundStyle(.secondary) }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: navigate).keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(20).frame(width: 340)
        .onAppear { value = String(model.currentPage) }
        .onChange(of: kind) { _ in value = String(kind == 0 ? model.currentPage : model.measureNumbers.first ?? 1) }
    }
    private func navigate() {
        guard valid, let number else { return }
        if kind == 0 { model.goToPage(number) } else { model.goToMeasure(number) }
        dismiss()
    }
}

struct ScoreLayoutSheet: View {
    @ObservedObject var model: ViewerModel
    @Environment(\.dismiss) private var dismiss
    @State private var layout = PageLayout()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Page Layout…").font(.headline)
            Form {
                Picker("Orientation", selection: $layout.landscape) { Text("Portrait").tag(false); Text("Landscape").tag(true) }
                Picker("Margins", selection: $layout.marginMM) {
                    ForEach([10, 15, 20, 25], id: \.self) { value in Text(verbatim: "\(value) mm").tag(value) }
                }
                Picker("Note Size", selection: $layout.noteSize) {
                    ForEach([75, 100, 125, 150], id: \.self) { value in Text(verbatim: "\(value)%").tag(value) }
                }
            }
            Text("Changes apply to the score, printing, and PDF. Paper size: A4.").font(.callout).foregroundStyle(.secondary)
            Text("Changing note size switches measures per line to Automatic.").font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { model.setPageLayout(layout); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 440)
        .onAppear { layout = model.pageLayout }
    }
}
