import AppKit
import UniformTypeIdentifiers

enum SlidesError: LocalizedError {
    case unsupportedFormat(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message), .corrupt(let message): message
        }
    }
}

/// The file formats Wired Slides opens and saves.
enum DocumentFormat: String, CaseIterable {
    case wslides, pptx

    var typeIdentifier: String {
        switch self {
        case .wslides: "com.wiredslides.wslides"
        case .pptx: "org.openxmlformats.presentationml.presentation"
        }
    }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .wslides: "Wired Slides Presentation"
        case .pptx: "PowerPoint Presentation (.pptx)"
        }
    }

    var shortName: String {
        switch self {
        case .wslides: "Wired Slides"
        case .pptx: "PowerPoint"
        }
    }

    var isNative: Bool { self == .wslides }

    static func from(typeName: String) -> DocumentFormat? {
        if let format = allCases.first(where: { $0.typeIdentifier == typeName }) { return format }
        if let type = UTType(typeName) {
            return allCases.first { UTType($0.typeIdentifier).map(type.conforms(to:)) ?? false }
                ?? allCases.first { type.preferredFilenameExtension == $0.fileExtension }
        }
        return allCases.first { $0.fileExtension == typeName.lowercased() }
    }

    func read(_ data: Data) throws -> Presentation {
        switch self {
        case .wslides: try WSlidesFormat.read(data)
        case .pptx: try PPTXReader.read(data)
        }
    }

    func write(_ presentation: Presentation) throws -> Data {
        switch self {
        case .wslides: try WSlidesFormat.write(presentation)
        case .pptx: try PPTXWriter.write(presentation)
        }
    }
}

/// The native format: a ZIP holding `presentation.json`, the media files and a preview.
enum WSlidesFormat {
    static let mimeType = "application/vnd.wiredslides.wslides"
    static let formatVersion = 1

    private struct Envelope: Codable {
        var formatVersion: Int
        var application: String
        var presentation: Presentation
        /// Media ids → original file names.
        var mediaNames: [String: String]
    }

    static func write(_ presentation: Presentation) throws -> Data {
        var stripped = presentation
        stripped.pruneMedia()
        let media = stripped.media
        stripped.media = [:]
        let envelope = Envelope(formatVersion: formatVersion, application: "Wired Slides",
                                presentation: stripped, mediaNames: media.mapValues(\.filename))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var entries: [(path: String, data: Data)] = [("mimetype", Data(mimeType.utf8))]
        entries.append(("presentation.json", try encoder.encode(envelope)))
        for (id, item) in media.sorted(by: { $0.key < $1.key }) {
            entries.append(("media/\(id)", item.data))
        }
        if let first = presentation.slides.first,
           let png = SlideRenderer.pngData(first, number: 1, presentation: presentation, pixelWidth: 512) {
            entries.append(("preview.png", png))
        }
        return ZipArchive.write(entries)
    }

    static func read(_ data: Data) throws -> Presentation {
        let entries: [String: Data]
        do {
            entries = try ZipArchive.read(data)
        } catch {
            throw SlidesError.corrupt("The presentation couldn't be read because it isn't a valid Wired Slides file.")
        }
        guard let json = entries["presentation.json"] else {
            throw SlidesError.corrupt("The presentation is missing its contents (presentation.json).")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: json)
        } catch {
            throw SlidesError.corrupt("The presentation couldn't be read: \(error.localizedDescription)")
        }
        guard envelope.formatVersion <= formatVersion else {
            throw SlidesError.unsupportedFormat("This presentation was made with a newer version of Wired Slides.")
        }
        var presentation = envelope.presentation
        for (id, name) in envelope.mediaNames {
            if let bytes = entries["media/\(id)"] { presentation.media[id] = MediaItem(filename: name, data: bytes) }
        }
        if presentation.slides.isEmpty {
            presentation.slides = [LayoutBuilder.makeSlide(.title, theme: presentation.theme, size: presentation.slideSize)]
        }
        return presentation
    }
}
