import XCTest
import WebKit
import PDFKit
@testable import NWCViewer

final class ViewerTests: XCTestCase {
    var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/nwc2xml") }
    func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "nwc", subdirectory: "Fixtures"))
    }
    func temporaryFile(_ data: Data, name: String = "input.nwc") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
    func testReadingHistoryPersistsIndependentScoresAndClears() throws {
        let suite = "NWCViewerTests.history." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try temporaryFile(Data("first".utf8))
        let second = try temporaryFile(Data("second".utf8))
        let state = ReadingState(voices: ["alto"], zoom: 1.25, fitWidth: false, page: 3, pageOffset: 0.4, measures: 6, layout: PageLayout(landscape: true, marginMM: 20, noteSize: 125))
        let history = ReadingHistory(defaults: defaults)
        history.save(url: first, state: state)
        history.save(url: second, state: ReadingState())
        let reopened = ReadingHistory(defaults: defaults)
        XCTAssertEqual(reopened.entries.first?.resolvedURL().resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
        XCTAssertEqual(reopened.state(for: first), state)
        XCTAssertEqual(reopened.state(for: second), ReadingState())
        reopened.save(url: first, state: state)
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertEqual(reopened.entries.first?.resolvedURL().resolvingSymlinksInPath(), first.resolvingSymlinksInPath())
        reopened.clear()
        XCTAssertTrue(ReadingHistory(defaults: defaults).entries.isEmpty)
    }

    func testFrenchLocalizationAndPluralPages() throws {
        let expected = ["de": "Öffnen…", "en": "Open…", "es": "Abrir…", "fr": "Ouvrir…", "it": "Apri…"]
        for (language, label) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Open…", value: nil, table: nil), label)
        }
        let path = try XCTUnwrap(Bundle.main.path(forResource: "fr", ofType: "lproj"))
        let french = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(french.localizedString(forKey: "Open…", value: nil, table: nil), "Ouvrir…")
        XCTAssertEqual(french.localizedString(forKey: "Save PDF…", value: nil, table: nil), "Enregistrer en PDF…")
        XCTAssertEqual(french.localizedString(forKey: "Unable to create PDF.", value: nil, table: nil), "Impossible de créer le PDF.")
        let format = french.localizedString(forKey: "page_count", value: nil, table: nil)
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "fr"), 1), "1 page")
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "fr"), 2), "2 pages")
    }

    func testCompressedAndUncompressedBinaryScores() throws {
        for name in ["Flee", "St._Stephen", "syllables", "Uncompressed", "Modern275"] {
            let url = try fixture(name)
            let original = try Data(contentsOf: url)
            let xml = try Converter(executable: helper).convert(url)
            XCTAssertTrue(xml.contains("<score-partwise"))
            XCTAssertTrue(xml.contains("<note"))
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("xml").path))
        }
    }
    func testSpacesUnicodeAndShellCharactersInFilename() throws {
        let file = try temporaryFile(Data(contentsOf: fixture("Flee")), name: "Choir 日本語 ' $score ;.nwc")
        XCTAssertNoThrow(try Converter(executable: helper).convert(file))
    }
    func testRenamedTextIsRejected() throws {
        let file = try temporaryFile(Data("!NoteWorthyComposer(2.75)\n|Note|Dur:4th|Pos:0".utf8))
        XCTAssertThrowsError(try Converter(executable: helper).convert(file))
    }
    func testTruncatedCompressedScoreIsRejected() throws {
        let file = try temporaryFile(Data("[NWZ]\0broken".utf8))
        XCTAssertThrowsError(try Converter(executable: helper).convert(file))
    }
    func testUnsupportedVersionIsRejected() throws {
        var data = try Data(contentsOf: fixture("Uncompressed"))
        let offset = Data("[NoteWorthy ArtWare]\0\0\0[NoteWorthy Composer]\0".utf8).count
        data[offset] = 0xff; data[offset + 1] = 0x7f
        let file = try temporaryFile(data)
        XCTAssertThrowsError(try Converter(executable: helper).convert(file))
    }
    func testMissingHelperHasUsefulError() throws {
        XCTAssertThrowsError(try Converter(executable: URL(fileURLWithPath: "/missing/nwc2xml")).convert(fixture("Flee"))) { error in
            XCTAssertEqual(error.localizedDescription, NSLocalizedString("The converter is missing. Reinstall NWC Viewer or rebuild it using the setup instructions.", comment: ""))
        }
    }
    func testMalformedOrEmptyMusicXMLIsRejected() {
        for text in ["", "<score-partwise>", "<html/>", "<score-partwise/>", "<!DOCTYPE a [<!ENTITY x 'bad'>]><score-partwise><note/></score-partwise>"] {
            XCTAssertThrowsError(try ScoreXML.validate(Data(text.utf8)))
        }
    }
    func testTimeoutTerminatesHelper() throws {
        // exec replaces the shell, so the timeout has no orphan child to clean up.
        let script = try temporaryFile(Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8), name: "slow-helper")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let start = Date()
        XCTAssertThrowsError(try Converter(executable: script, timeout: 0.1).convert(fixture("Flee")))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    @MainActor
    func testModelRestoresVoicesZoomPageAndLayout() async throws {
        let originalMeasures = UserDefaults.standard.object(forKey: "measuresPerLine")
        defer { UserDefaults.standard.set(originalMeasures, forKey: "measuresPerLine") }
        let suite = "NWCViewerTests.model." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = try temporaryFile(Data(contentsOf: fixture("Flee")))
        let history = ReadingHistory(defaults: defaults)
        let model = ViewerModel(history: history)
        let loaded = expectation(description: "Renderer ready")
        let delegate = NavigationWaiter(loaded)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.navigationDelegate = delegate
        model.webView = view
        let page = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web"))
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        await fulfillment(of: [loaded], timeout: 15)
        model.pageLoaded(); model.open(file)
        try await waitUntilReady(model)
        let voice = try XCTUnwrap(model.parts.first?.id)
        model.setVisibleParts([voice]); try await waitUntilReady(model)
        model.setMeasuresPerLine(2); try await waitUntilReady(model)
        model.setZoom(1.5)
        let target = min(2, model.pageCount)
        model.goToPage(target)
        try await Task.sleep(nanoseconds: 200_000_000)
        let rawPosition = try await view.evaluateJavaScript("viewer.position()")
        let position = try XCTUnwrap(rawPosition as? [String: Any])
        model.receivePosition(position)
        model.setZoom(1.0)
        model.setZoom(1.5)
        try await Task.sleep(nanoseconds: 100_000_000)
        let zoomedPosition = try await view.evaluateJavaScript("viewer.position()") as? [String: Any]
        XCTAssertEqual(zoomedPosition?["page"] as? Int, target)
        let saved = try XCTUnwrap(history.state(for: file))
        XCTAssertEqual(saved.zoom, 1.5)
        XCTAssertFalse(saved.fitWidth)
        XCTAssertEqual(saved.page, target)
        if model.parts.count > 1 { XCTAssertEqual(saved.voices, [voice]) }
        model.showingSidebar = true; model.prepareThumbnails()
        for _ in 0..<200 where model.preparingThumbnails { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(model.thumbnailDocument?.pageCount, model.pageCount)
        let savedZoom = try await view.evaluateJavaScript("document.getElementById('score').style.zoom") as? String
        XCTAssertEqual(savedZoom, "1.5")
        let reopened = ViewerModel(history: ReadingHistory(defaults: defaults))
        reopened.webView = view; reopened.pageLoaded()
        try await waitUntilReady(reopened)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(reopened.selectedPartIDs, [voice])
        XCTAssertEqual(reopened.zoom, 1.5)
        XCTAssertEqual(reopened.currentPage, target)
        XCTAssertEqual(reopened.measuresPerLine, 2)
        let rawRestored = try await view.evaluateJavaScript("viewer.position()")
        let restored = try XCTUnwrap(rawRestored as? [String: Any])
        XCTAssertEqual(restored["page"] as? Int, target)
        XCTAssertEqual(restored["offset"] as? Double ?? -1, saved.pageOffset, accuracy: 0.02)
    }
    @MainActor
    private func waitUntilReady(_ model: ViewerModel) async throws {
        for _ in 0..<500 {
            if model.ready { return }
            if let error = model.error { XCTFail(error); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Score did not become ready")
    }

    @MainActor
    func testBundledRendererInWebKit() async throws {
        let loaded = expectation(description: "Local WebKit renderer loaded")
        let delegate = NavigationWaiter(loaded)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 800))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.navigationDelegate = delegate
        let page = try XCTUnwrap(Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web"))
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        await fulfillment(of: [loaded], timeout: 15)
        XCTAssertNil(delegate.error)
        let xml = try Converter(executable: helper).convert(fixture("Flee"))
        _ = try await view.callAsyncJavaScript("await window.viewer.load(xml, 0);", arguments: ["xml": xml], in: nil, contentWorld: .page)
        let pages = try await view.evaluateJavaScript("document.querySelectorAll('.music-page svg').length") as? Int
        XCTAssertGreaterThan(pages ?? 0, 0)
        _ = try await view.callAsyncJavaScript("window.viewer.zoom(value)", arguments: ["value": 1.5], in: nil, contentWorld: .page)
        let zoom = try await view.evaluateJavaScript("document.getElementById('score').style.zoom") as? String
        XCTAssertEqual(zoom, "1.5")
        for scale in [0.5, 1.0, 2.0] {
            _ = try await view.callAsyncJavaScript("window.viewer.zoom(value)", arguments: ["value": scale], in: nil, contentWorld: .page)
            let pdf = try await ScorePDF.make(from: view)
            XCTAssertEqual(pdf.pageCount, pages)
            for index in 0..<pdf.pageCount {
                let page = try XCTUnwrap(pdf.page(at: index))
                XCTAssertEqual(page.bounds(for: .mediaBox).width, 595.2756, accuracy: 0.1)
                XCTAssertEqual(page.bounds(for: .mediaBox).height, 841.8898, accuracy: 0.1)
                XCTAssertGreaterThan(page.dataRepresentation?.count ?? 0, 5000, "PDF page must contain rendered music")
            }
        }

        for measures in [4, 2, 8, 0] {
            _ = try await view.callAsyncJavaScript("await window.viewer.load(xml, measures)", arguments: ["xml": xml, "measures": measures], in: nil, contentWorld: .page)
            let info = try await view.evaluateJavaScript("window.viewer.layoutInfo()") as? [String: Any]
            let lines = try XCTUnwrap(info?["measuresPerLine"] as? [Int])
            XCTAssertFalse(lines.isEmpty)
            if measures > 0 {
                XCTAssertTrue(lines.dropLast().allSatisfy { $0 == measures })
                XCTAssertLessThanOrEqual(lines.last ?? 0, measures)
            }
            let pdf = try await ScorePDF.make(from: view)
            XCTAssertEqual(pdf.pageCount, info?["pages"] as? Int)
        }

        let voicesURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Voices", withExtension: "musicxml", subdirectory: "Fixtures"))
        let voicesXML = try String(contentsOf: voicesURL, encoding: .utf8)
        _ = try await view.callAsyncJavaScript("await viewer.load(xml,4)", arguments: ["xml": voicesXML], in: nil, contentWorld: .page)
        let info = try await view.callAsyncJavaScript("return await viewer.configure(4, ['alto'])", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(info?["renderedPartCount"] as? Int, 1)
        XCTAssertEqual(info?["sourceMeasureCount"] as? Int, 4)
        let soloPDF = try await ScorePDF.make(from: view)
        let text = soloPDF.string ?? ""
        XCTAssertTrue(text.contains("AltoTest"))
        XCTAssertFalse(text.contains("SopranoTest"))
        XCTAssertFalse(text.contains("BassTest"))

        // Navigation and layout must refer to the actual printed score.
        let landscapeInfo = try await view.callAsyncJavaScript("return await viewer.configure(0, ['alto'], { landscape: true, marginMM: 25, noteSize: 150 })", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(landscapeInfo?["notationScale"] as? Double, 1.5)
        let navigation = try XCTUnwrap(landscapeInfo?["navigation"] as? [[String: Any]])
        XCTAssertEqual(navigation.compactMap { $0["number"] as? Int }, [1, 2, 3, 4])
        let jumped = try await view.evaluateJavaScript("viewer.goToMeasure(3)") as? Bool
        XCTAssertEqual(jumped, true)
        let missing = try await view.evaluateJavaScript("viewer.goToMeasure(999)") as? Bool
        XCTAssertEqual(missing, false)
        let landscapePDF = try await ScorePDF.make(from: view, landscape: true)
        let landscapePage = try XCTUnwrap(landscapePDF.page(at: 0))
        XCTAssertEqual(landscapePage.bounds(for: .mediaBox).width, 841.8898, accuracy: 0.1)
        XCTAssertEqual(landscapePage.bounds(for: .mediaBox).height, 595.2756, accuracy: 0.1)
        XCTAssertTrue(landscapePDF.string?.contains("AltoTest") == true)
        XCTAssertFalse(landscapePDF.string?.contains("SopranoTest") == true)
        let changedFile = try await view.callAsyncJavaScript("return await viewer.load(xml, 4, ['deleted-voice'])", arguments: ["xml": voicesXML], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(changedFile?["renderedPartCount"] as? Int, 3)

    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    var error: Error?
    init(_ loaded: XCTestExpectation) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error; loaded.fulfill()
    }
}
