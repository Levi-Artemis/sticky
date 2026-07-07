import Foundation
import SwiftUI

enum NoteImageAlignment: String, Codable, Equatable {
    case left
    case center
    case right
}

struct NoteTextStyleRun: Codable, Equatable {
    var location: Int
    var length: Int
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var fontSize: Double?

    init(
        location: Int,
        length: Int,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikethrough: Bool = false,
        fontSize: Double? = nil
    ) {
        self.location = location
        self.length = length
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.fontSize = fontSize
    }

    private enum CodingKeys: String, CodingKey {
        case location
        case length
        case bold
        case italic
        case underline
        case strikethrough
        case fontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        location = try container.decodeIfPresent(Int.self, forKey: .location) ?? 0
        length = try container.decodeIfPresent(Int.self, forKey: .length) ?? 0
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encode(length, forKey: .length)
        try container.encode(bold, forKey: .bold)
        try container.encode(italic, forKey: .italic)
        try container.encode(underline, forKey: .underline)
        try container.encode(strikethrough, forKey: .strikethrough)
        try container.encodeIfPresent(fontSize, forKey: .fontSize)
    }

    var hasVisibleStyle: Bool {
        bold || italic || underline || strikethrough || fontSize != nil
    }

    func hasSameStyle(as other: NoteTextStyleRun) -> Bool {
        bold == other.bold
            && italic == other.italic
            && underline == other.underline
            && strikethrough == other.strikethrough
            && normalizedFontSize == other.normalizedFontSize
    }

    private var normalizedFontSize: Int? {
        fontSize.map { Int(($0 * 10).rounded()) }
    }

    static func normalized(_ runs: [NoteTextStyleRun], textLength: Int) -> [NoteTextStyleRun] {
        let sortedRuns = runs
            .filter { $0.length > 0 && $0.hasVisibleStyle }
            .compactMap { run -> NoteTextStyleRun? in
                let location = min(max(0, run.location), textLength)
                let end = min(max(location, run.location + run.length), textLength)
                guard end > location else { return nil }
                var clampedRun = run
                clampedRun.location = location
                clampedRun.length = end - location
                return clampedRun
            }
            .sorted { left, right in
                if left.location == right.location {
                    return left.length < right.length
                }
                return left.location < right.location
            }

        var normalizedRuns: [NoteTextStyleRun] = []
        for run in sortedRuns {
            if var previous = normalizedRuns.last,
               previous.location + previous.length == run.location,
               previous.hasSameStyle(as: run)
            {
                previous.length += run.length
                normalizedRuns[normalizedRuns.count - 1] = previous
            } else {
                normalizedRuns.append(run)
            }
        }
        return normalizedRuns
    }

    static func adjustedForReplacement(
        _ runs: [NoteTextStyleRun],
        replacedRange: NSRange,
        insertedLength: Int,
        newTextLength: Int
    ) -> [NoteTextStyleRun] {
        let replacementStart = replacedRange.location
        let replacementEnd = replacedRange.location + replacedRange.length
        let delta = insertedLength - replacedRange.length
        var adjustedRuns: [NoteTextStyleRun] = []

        for run in runs {
            let runStart = run.location
            let runEnd = run.location + run.length

            if runEnd <= replacementStart {
                adjustedRuns.append(run)
            } else if runStart >= replacementEnd {
                var shiftedRun = run
                shiftedRun.location += delta
                adjustedRuns.append(shiftedRun)
            } else {
                if runStart < replacementStart {
                    var leftRun = run
                    leftRun.length = replacementStart - runStart
                    adjustedRuns.append(leftRun)
                }

                if runEnd > replacementEnd {
                    var rightRun = run
                    rightRun.location = replacementStart + insertedLength
                    rightRun.length = runEnd - replacementEnd
                    adjustedRuns.append(rightRun)
                }
            }
        }

        return normalized(adjustedRuns, textLength: newTextLength)
    }
}

struct NoteImage: Codable, Identifiable, Equatable {
    var id = UUID()
    var data: Data
    // Stored in points for the inline rendered size. The original image remains in `data`.
    var width: Double
    var height: Double
    var alignment: NoteImageAlignment

    init(
        id: UUID = UUID(),
        data: Data,
        width: Double,
        height: Double,
        alignment: NoteImageAlignment = .left
    ) {
        self.id = id
        self.data = data
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case data
        case width
        case height
        case alignment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        data = try container.decode(Data.self, forKey: .data)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 220
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 180
        alignment = try container.decodeIfPresent(NoteImageAlignment.self, forKey: .alignment) ?? .left
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(data, forKey: .data)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(alignment, forKey: .alignment)
    }
}

struct NoteModel: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var images: [NoteImage] = []
    var styleRuns: [NoteTextStyleRun] = []
    var colorIndex = 0
    var isPinned = false
    var fontSize = 14.0
    var positionX = 300.0
    var positionY = 300.0
    var width = 260.0
    var height = 260.0

    static let imagePlaceholder = "\u{fffc}"
    static let imagePlaceholderCharacter: Character = "\u{fffc}"

    init(
        id: UUID = UUID(),
        text: String = "",
        images: [NoteImage] = [],
        styleRuns: [NoteTextStyleRun] = [],
        colorIndex: Int = 0,
        isPinned: Bool = false,
        fontSize: Double = 14.0,
        positionX: Double = 300.0,
        positionY: Double = 300.0,
        width: Double = 260.0,
        height: Double = 260.0
    ) {
        self.id = id
        self.text = text
        self.images = images
        self.styleRuns = styleRuns
        self.colorIndex = colorIndex
        self.isPinned = isPinned
        self.fontSize = fontSize
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case images
        case styleRuns
        case colorIndex
        case isPinned
        case fontSize
        case positionX
        case positionY
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        images = try container.decodeIfPresent([NoteImage].self, forKey: .images) ?? []
        let rawStyleRuns = try container.decodeIfPresent([NoteTextStyleRun].self, forKey: .styleRuns) ?? []
        styleRuns = NoteTextStyleRun.normalized(
            rawStyleRuns,
            textLength: (text as NSString).length
        )
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 14.0
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 300.0
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY) ?? 300.0
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 260.0
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 260.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(images, forKey: .images)
        try container.encode(styleRuns, forKey: .styleRuns)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    static let colors: [Color] = [
        Color(red: 1, green: 0.98, blue: 0.7),
        Color(red: 0.7, green: 0.9, blue: 0.7),
        Color(red: 0.7, green: 0.8, blue: 1.0),
        Color(red: 1, green: 0.75, blue: 0.8),
        Color(red: 0.85, green: 0.75, blue: 1.0),
    ]

    var color: Color {
        Self.colors[colorIndex % Self.colors.count]
    }

    mutating func nextColor() {
        colorIndex = (colorIndex + 1) % Self.colors.count
    }

    @discardableResult
    mutating func ensureInlineImagePlaceholders() -> Bool {
        let placeholderCount = text.reduce(0) { count, character in
            count + (character == Self.imagePlaceholderCharacter ? 1 : 0)
        }
        let missingCount = images.count - placeholderCount
        guard missingCount > 0 else { return false }

        let missingPlaceholders = Array(repeating: Self.imagePlaceholder, count: missingCount)
            .joined(separator: "\n")
        text = text.isEmpty ? missingPlaceholders : "\(missingPlaceholders)\n\(text)"
        return true
    }

    @discardableResult
    mutating func normalizeLegacyImageDisplaySizes(
        maxWidth: Double = 220,
        maxHeight: Double = 180
    ) -> Bool {
        let hasInlineImagePlaceholders = text.contains(Self.imagePlaceholder)
        guard !hasInlineImagePlaceholders else { return false }

        var changed = false
        for index in images.indices {
            let width = images[index].width
            let height = images[index].height
            guard width > 0, height > 0 else { continue }

            let scale = min(1.0, maxWidth / width, maxHeight / height)
            if scale < 1.0 {
                images[index].width = width * scale
                images[index].height = height * scale
                changed = true
            }
        }

        return changed
    }
}
