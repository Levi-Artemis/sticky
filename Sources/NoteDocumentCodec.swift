import AppKit
import Foundation

enum NoteDocumentCodec {
    static let documentExtension = "stickynotes"

    static func encodeDocument(notes: [NoteModel]) throws -> Data {
        let document = StickyNotesDocument(version: 1, notes: notes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decodeDocument(data: Data) throws -> [NoteModel] {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(StickyNotesDocument.self, from: data) {
            return document.notes
        }
        if let notes = try? decoder.decode([NoteModel].self, from: data) {
            return notes
        }
        if let note = try? decoder.decode(NoteModel.self, from: data) {
            return [note]
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    static func writeMarkdown(note: NoteModel, to url: URL) throws {
        let assetFolderName = "\(url.deletingPathExtension().lastPathComponent)-assets"
        let assetFolderURL = url.deletingLastPathComponent()
            .appendingPathComponent(assetFolderName, isDirectory: true)

        if !note.images.isEmpty {
            try FileManager.default.createDirectory(
                at: assetFolderURL,
                withIntermediateDirectories: true
            )
            for (index, image) in note.images.enumerated() {
                let imageURL = assetFolderURL.appendingPathComponent(
                    imageFileName(for: image, index: index)
                )
                try image.data.write(to: imageURL, options: .atomic)
            }
        }

        let markdown = markdownString(for: note, assetFolderName: assetFolderName)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    static func readMarkdown(from url: URL) throws -> NoteModel {
        let markdown = try String(contentsOf: url, encoding: .utf8)
        var parser = MarkdownNoteParser(baseURL: url.deletingLastPathComponent())
        return parser.parse(markdown)
    }

    private static func markdownString(
        for note: NoteModel,
        assetFolderName: String
    ) -> String {
        let text = note.text
        let normalizedStyleRuns = NoteTextStyleRun.normalized(
            note.styleRuns,
            textLength: (text as NSString).length
        )
        var markdown = ""
        var currentStyle = MarkdownStyle()
        var utf16Location = 0
        var imageIndex = 0

        for character in text {
            let characterString = String(character)
            let characterLength = (characterString as NSString).length

            if character == NoteModel.imagePlaceholderCharacter {
                markdown += closeMarkdownStyle(currentStyle)
                currentStyle = MarkdownStyle()

                if imageIndex < note.images.count {
                    let image = note.images[imageIndex]
                    let path = "\(assetFolderName)/\(imageFileName(for: image, index: imageIndex))"
                    if !markdown.hasSuffix("\n") && !markdown.isEmpty {
                        markdown += "\n"
                    }
                    markdown += "![image](\(path))\n"
                    imageIndex += 1
                }
                utf16Location += characterLength
                continue
            }

            let style = markdownStyle(at: utf16Location, in: normalizedStyleRuns)
            if style != currentStyle {
                markdown += closeMarkdownStyle(currentStyle)
                markdown += openMarkdownStyle(style)
                currentStyle = style
            }

            markdown += escapedMarkdownText(characterString)
            utf16Location += characterLength
        }

        markdown += closeMarkdownStyle(currentStyle)
        return markdown
    }

    private static func markdownStyle(
        at location: Int,
        in runs: [NoteTextStyleRun]
    ) -> MarkdownStyle {
        var style = MarkdownStyle()
        for run in runs where run.location <= location && location < run.location + run.length {
            style.bold = style.bold || run.bold
            style.italic = style.italic || run.italic
            style.underline = style.underline || run.underline
            style.strikethrough = style.strikethrough || run.strikethrough
            if let fontSize = run.fontSize {
                style.fontSize = fontSize
            }
        }
        return style
    }

    private static func openMarkdownStyle(_ style: MarkdownStyle) -> String {
        var output = ""
        if let fontSize = style.fontSize {
            output += "<span style=\"font-size: \(formatFontSize(fontSize))pt\">"
        }
        if style.underline {
            output += "<u>"
        }
        if style.strikethrough {
            output += "~~"
        }
        if style.bold {
            output += "**"
        }
        if style.italic {
            output += "*"
        }
        return output
    }

    private static func closeMarkdownStyle(_ style: MarkdownStyle) -> String {
        var output = ""
        if style.italic {
            output += "*"
        }
        if style.bold {
            output += "**"
        }
        if style.strikethrough {
            output += "~~"
        }
        if style.underline {
            output += "</u>"
        }
        if style.fontSize != nil {
            output += "</span>"
        }
        return output
    }

    private static func escapedMarkdownText(_ text: String) -> String {
        var output = ""
        for character in text {
            if "\\`*_{}[]()#+-.!|~".contains(character) {
                output.append("\\")
            }
            output.append(character)
        }
        return output
    }

    private static func imageFileName(for image: NoteImage, index: Int) -> String {
        "image-\(index + 1)-\(image.id.uuidString).png"
    }

    private static func formatFontSize(_ size: Double) -> String {
        if floor(size) == size {
            return String(Int(size))
        }
        return String(format: "%.1f", size)
    }
}

private struct StickyNotesDocument: Codable {
    var version: Int
    var notes: [NoteModel]
}

private struct MarkdownStyle: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var fontSize: Double?

    var hasVisibleStyle: Bool {
        bold || italic || underline || strikethrough || fontSize != nil
    }
}

private struct MarkdownNoteParser {
    let baseURL: URL
    private var text = ""
    private var images: [NoteImage] = []
    private var styleRuns: [NoteTextStyleRun] = []
    private var activeStyle = MarkdownStyle()

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    mutating func parse(_ markdown: String) -> NoteModel {
        var index = markdown.startIndex

        while index < markdown.endIndex {
            if let image = parseImage(in: markdown, at: index) {
                appendImage(at: image.path)
                index = image.nextIndex
            } else if markdown[index...].hasPrefix("~~") {
                activeStyle.strikethrough.toggle()
                index = markdown.index(index, offsetBy: 2)
            } else if markdown[index...].hasPrefix("**") {
                activeStyle.bold.toggle()
                index = markdown.index(index, offsetBy: 2)
            } else if markdown[index...].hasPrefix("*") {
                activeStyle.italic.toggle()
                index = markdown.index(after: index)
            } else if markdown[index...].hasPrefix("<u>") {
                activeStyle.underline = true
                index = markdown.index(index, offsetBy: 3)
            } else if markdown[index...].hasPrefix("</u>") {
                activeStyle.underline = false
                index = markdown.index(index, offsetBy: 4)
            } else if let span = parseFontSizeSpan(in: markdown, at: index) {
                activeStyle.fontSize = span.fontSize
                index = span.nextIndex
            } else if markdown[index...].hasPrefix("</span>") {
                activeStyle.fontSize = nil
                index = markdown.index(index, offsetBy: 7)
            } else if markdown[index] == "\\",
                      markdown.index(after: index) < markdown.endIndex
            {
                let nextIndex = markdown.index(after: index)
                appendText(String(markdown[nextIndex]))
                index = markdown.index(after: nextIndex)
            } else {
                appendText(String(markdown[index]))
                index = markdown.index(after: index)
            }
        }

        return NoteModel(
            text: text,
            images: images,
            styleRuns: NoteTextStyleRun.normalized(
                styleRuns,
                textLength: (text as NSString).length
            )
        )
    }

    private mutating func appendText(_ value: String) {
        let location = (text as NSString).length
        text += value
        let length = (value as NSString).length
        guard activeStyle.hasVisibleStyle, length > 0 else { return }

        let run = NoteTextStyleRun(
            location: location,
            length: length,
            bold: activeStyle.bold,
            italic: activeStyle.italic,
            underline: activeStyle.underline,
            strikethrough: activeStyle.strikethrough,
            fontSize: activeStyle.fontSize
        )

        if var previous = styleRuns.last,
           previous.location + previous.length == run.location,
           previous.hasSameStyle(as: run)
        {
            previous.length += run.length
            styleRuns[styleRuns.count - 1] = previous
        } else {
            styleRuns.append(run)
        }
    }

    private mutating func appendImage(at rawPath: String) {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL: URL
        if trimmedPath.hasPrefix("file://"), let url = URL(string: trimmedPath) {
            imageURL = url
        } else if trimmedPath.hasPrefix("/") {
            imageURL = URL(fileURLWithPath: trimmedPath)
        } else {
            imageURL = baseURL.appendingPathComponent(trimmedPath)
        }

        guard let data = try? Data(contentsOf: imageURL),
              let image = Self.makeNoteImage(from: data)
        else {
            appendText("![image](\(rawPath))")
            return
        }

        text += NoteModel.imagePlaceholder
        images.append(image)
    }

    private func parseImage(
        in markdown: String,
        at index: String.Index
    ) -> (path: String, nextIndex: String.Index)? {
        guard markdown[index...].hasPrefix("![") else { return nil }
        guard let closeAlt = markdown[index...].firstIndex(of: "]") else { return nil }
        let openParen = markdown.index(after: closeAlt)
        guard openParen < markdown.endIndex,
              markdown[openParen] == "("
        else { return nil }

        let pathStart = markdown.index(after: openParen)
        guard let closeParen = markdown[pathStart...].firstIndex(of: ")") else { return nil }
        let path = String(markdown[pathStart..<closeParen])
        return (path, markdown.index(after: closeParen))
    }

    private func parseFontSizeSpan(
        in markdown: String,
        at index: String.Index
    ) -> (fontSize: Double, nextIndex: String.Index)? {
        let prefix = "<span style=\"font-size:"
        guard markdown[index...].hasPrefix(prefix) else { return nil }
        let valueStart = markdown.index(index, offsetBy: prefix.count)
        guard let tagEnd = markdown[valueStart...].firstIndex(of: ">") else { return nil }
        let value = markdown[valueStart..<tagEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "pt", with: "")
            .replacingOccurrences(of: "px", with: "")
        guard let fontSize = Double(value) else { return nil }
        return (fontSize, markdown.index(after: tagEnd))
    }

    private static func makeNoteImage(from data: Data) -> NoteImage? {
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else { return nil }

        let pngData = bitmap.representation(using: .png, properties: [:]) ?? data
        let originalWidth = Double(bitmap.pixelsWide)
        let originalHeight = Double(bitmap.pixelsHigh)
        let scale = min(1.0, 220.0 / originalWidth, 180.0 / originalHeight)

        return NoteImage(
            data: pngData,
            width: originalWidth * scale,
            height: originalHeight * scale,
            alignment: .left
        )
    }
}
