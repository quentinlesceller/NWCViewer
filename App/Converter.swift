import Darwin
import Foundation

enum ViewerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return NSLocalizedString(text, comment: "User-facing error") }; return nil }
}

struct ScoreXML {
    static func validate(_ data: Data) throws -> String {
        guard data.count <= 32 * 1024 * 1024, let xml = String(data: data, encoding: .utf8),
              !xml.uppercased().contains("<!ENTITY") else {
            throw ViewerError.message("The converter returned an unreadable score.")
        }
        let reader = RootReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), reader.root == "score-partwise", reader.hasNotes else {
            throw ViewerError.message("This file could not be converted to a readable score. It may be damaged or use an unsupported NWC version. Supported versions: 1.30–2.1 / 2.75.")
        }
        return xml
    }
    private final class RootReader: NSObject, XMLParserDelegate {
        var root: String?
        var hasNotes = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if root == nil { root = name }
            if name == "note" { hasNotes = true }
        }
    }
}

struct Converter {
    let executable: URL
    var timeout: TimeInterval = 20

    func convert(_ source: URL) throws -> String {
        let fm = FileManager.default
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 16 * 1024 * 1024 else {
            throw ViewerError.message("Choose a non-empty NWC file smaller than 16 MB.")
        }
        let data = try Data(contentsOf: source)
        guard data.starts(with: Data("[NWZ]\0".utf8)) || data.starts(with: Data("[NoteWorthy ArtWare]\0\0\0[NoteWorthy Composer]\0".utf8)) else {
            throw ViewerError.message("This is not a binary NoteWorthy Composer file. Choose the original .nwc file; changing a file’s extension does not convert it.")
        }
        guard fm.isExecutableFile(atPath: executable.path) else {
            throw ViewerError.message("The converter is missing. Reinstall NWC Viewer or rebuild it using the setup instructions.")
        }
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let input = work.appendingPathComponent("score.nwc")
        try data.write(to: input, options: .atomic)
        // Never invoke a shell or allow the converter to write beside the original.
        let process = Process()
        process.executableURL = executable
        process.arguments = [input.path]
        process.currentDirectoryURL = work
        process.environment = ProcessInfo.processInfo.environment.merging(["TMPDIR": work.path]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            // Enforce the conversion deadline before removing the temporary directory.
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            throw ViewerError.message("This file took too long to convert. It may be damaged or unsupported.")
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0,
              let result = try? Data(contentsOf: work.appendingPathComponent("score.xml")) else {
            throw ViewerError.message("This file could not be opened. It may be damaged or use an unsupported NWC version. Supported versions: 1.30–2.1 / 2.75.")
        }
        return try ScoreXML.validate(result)
    }
}
