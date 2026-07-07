import AppKit
import SwiftUI

private enum NoteImageCommand {
    case originalSize
    case fitWidth
    case shrink
    case grow
    case align(NoteImageAlignment)
}

enum NoteTextStyleAction: Equatable {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case toggleStrikethrough
    case resetPlainText
    case decreaseFontSize
    case increaseFontSize
}

struct NoteTextStyleCommand: Equatable {
    let id = UUID()
    let action: NoteTextStyleAction
}

enum NoteTextStyleCommandUserInfo {
    static let noteID = "noteID"
    static let action = "action"
}

extension Notification.Name {
    static let noteTextStyleCommand = Notification.Name("StickyNotesNoteTextStyleCommand")
}

struct PasteAwareTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var images: [NoteImage]
    @Binding var styleRuns: [NoteTextStyleRun]
    @Binding var selectedRange: NSRange
    @Binding var pendingStyleCommand: NoteTextStyleCommand?
    let noteID: UUID
    var fontSize: Double
    var textColor: NSColor
    var onContentChange: (String, [NoteImage], [NoteTextStyleRun]) -> Void
    var onOpenImage: (NoteImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = ImagePasteTextView()
        textView.delegate = context.coordinator
        textView.onPasteImages = { images in
            context.coordinator.insertPastedImages(images, into: textView)
        }
        textView.onOpenImage = { imageID in
            context.coordinator.openImage(with: imageID)
        }
        textView.onImageCommand = { imageID, command, textView in
            context.coordinator.applyImageCommand(command, to: imageID, in: textView)
        }
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        context.coordinator.startObservingStyleCommands(in: textView)
        scrollView.documentView = textView
        context.coordinator.render(parent: self, in: textView, preserveSelection: false)
        textView.typingAttributes = textAttributes
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ImagePasteTextView else { return }

        let signature = contentSignature(text: text, images: images, styleRuns: styleRuns)
        let styleSignature = "\(fontSize)-\(textColor)"
        let needsRender = context.coordinator.renderedSignature != signature
            || context.coordinator.renderedStyleSignature != styleSignature
        if needsRender {
            context.coordinator.render(parent: self, in: textView, preserveSelection: true)
            textView.typingAttributes = textAttributes
        }

        if let command = pendingStyleCommand,
           context.coordinator.appliedStyleCommandID != command.id
        {
            context.coordinator.appliedStyleCommandID = command.id
            context.coordinator.applyTextStyleCommand(command.action, in: textView)
            let pendingStyleCommandBinding = $pendingStyleCommand
            DispatchQueue.main.async {
                pendingStyleCommandBinding.wrappedValue = nil
            }
        }
    }

    fileprivate var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: textColor,
        ]
    }

    fileprivate func contentSignature(
        text: String,
        images: [NoteImage],
        styleRuns: [NoteTextStyleRun]
    ) -> String {
        let imageSignature = images.map { image in
            "\(image.id.uuidString):\(Int(image.width)):\(Int(image.height)):\(image.alignment.rawValue):\(image.data.count)"
        }.joined(separator: "|")
        let textLength = (text as NSString).length
        let styleSignature = NoteTextStyleRun.normalized(styleRuns, textLength: textLength)
            .map { run in
                "\(run.location):\(run.length):\(run.bold):\(run.italic):\(run.underline):\(run.strikethrough):\(run.fontSize.map { String(format: "%.1f", $0) } ?? "-")"
            }
            .joined(separator: "|")
        return "\(text)|\(imageSignature)|\(styleSignature)"
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareTextEditor
        var imageMap: [UUID: NoteImage] = [:]
        var renderedSignature = ""
        var renderedStyleSignature = ""
        var appliedStyleCommandID: UUID?
        private weak var observedTextView: ImagePasteTextView?
        private var textStyleCommandObserver: NSObjectProtocol?
        private var isRendering = false

        init(_ parent: PasteAwareTextEditor) {
            self.parent = parent
        }

        deinit {
            if let textStyleCommandObserver {
                NotificationCenter.default.removeObserver(textStyleCommandObserver)
            }
        }

        fileprivate func startObservingStyleCommands(in textView: ImagePasteTextView) {
            observedTextView = textView
            guard textStyleCommandObserver == nil else { return }

            textStyleCommandObserver = NotificationCenter.default.addObserver(
                forName: .noteTextStyleCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let textView = self.observedTextView,
                      let noteID = notification.userInfo?[NoteTextStyleCommandUserInfo.noteID] as? UUID,
                      noteID == self.parent.noteID,
                      let action = notification.userInfo?[NoteTextStyleCommandUserInfo.action] as? NoteTextStyleAction
                else { return }

                self.applyTextStyleCommand(action, in: textView)
                textView.window?.makeFirstResponder(textView)
            }
        }

        fileprivate func render(
            parent: PasteAwareTextEditor,
            in textView: ImagePasteTextView,
            preserveSelection: Bool
        ) {
            self.parent = parent
            imageMap = Dictionary(uniqueKeysWithValues: parent.images.map { ($0.id, $0) })
            let selectedRange = preserveSelection ? parent.selectedRange : textView.selectedRange()
            let attributedString = makeAttributedString(
                text: parent.text,
                images: parent.images,
                styleRuns: parent.styleRuns,
                attributes: parent.textAttributes
            )

            isRendering = true
            textView.textStorage?.setAttributedString(attributedString)
            if preserveSelection {
                let preservedRange = NSRange(
                    location: min(selectedRange.location, attributedString.length),
                    length: min(selectedRange.length, max(0, attributedString.length - selectedRange.location))
                )
                textView.setSelectedRange(preservedRange)
                parent.selectedRange = preservedRange
            }
            isRendering = false

            renderedSignature = parent.contentSignature(
                text: parent.text,
                images: parent.images,
                styleRuns: parent.styleRuns
            )
            renderedStyleSignature = "\(parent.fontSize)-\(parent.textColor)"
            textView.refreshHoverControls()
        }

        func textDidChange(_ notification: Notification) {
            guard !isRendering,
                  let textView = notification.object as? ImagePasteTextView
            else { return }
            syncContent(from: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isRendering,
                  let textView = notification.object as? NSTextView
            else { return }
            parent.selectedRange = textView.selectedRange()
        }

        fileprivate func insertPastedImages(_ pastedImages: [NSImage], into textView: ImagePasteTextView) {
            let noteImages = pastedImages.compactMap(Self.makeNoteImage)
            guard !noteImages.isEmpty else { return }

            for image in noteImages {
                imageMap[image.id] = image
            }

            let insertion = NSMutableAttributedString()
            let selectedRange = textView.selectedRange()
            let text = textView.string as NSString
            if selectedRange.location > 0,
               text.substring(with: NSRange(location: selectedRange.location - 1, length: 1)) != "\n"
            {
                insertion.append(NSAttributedString(string: "\n", attributes: parent.textAttributes))
            }

            for (index, image) in noteImages.enumerated() {
                if index > 0 {
                    insertion.append(NSAttributedString(string: "\n", attributes: parent.textAttributes))
                }
                insertion.append(
                    Self.makeImageAttributedString(for: image)
                )
            }

            if selectedRange.location < text.length,
               text.substring(with: NSRange(location: selectedRange.location, length: 1)) != "\n"
            {
                insertion.append(NSAttributedString(string: "\n", attributes: parent.textAttributes))
            }

            textView.insertText(insertion, replacementRange: selectedRange)
            syncContent(from: textView)
        }

        fileprivate func applyTextStyleCommand(
            _ action: NoteTextStyleAction,
            in textView: ImagePasteTextView
        ) {
            guard let storage = textView.textStorage else { return }

            let textLength = storage.length
            guard textLength > 0 else {
                textView.typingAttributes = typingAttributes(
                    byApplying: action,
                    to: textView.typingAttributes
                )
                return
            }

            let range = textStyleTargetRange(in: textView, textLength: textLength)
            guard range.length > 0 else { return }

            let targetState = targetState(for: action, in: storage, range: range)
            var updates: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
                if attributes[.attachment] != nil { return }
                updates.append(
                    (
                        subrange,
                        attributesByApplying(
                            action: action,
                            targetState: targetState,
                            to: attributes
                        )
                    )
                )
            }

            storage.beginEditing()
            for update in updates {
                storage.setAttributes(update.attributes, range: update.range)
            }
            storage.endEditing()
            textView.layoutManager?.invalidateDisplay(forCharacterRange: range)
            textView.needsDisplay = true

            textView.setSelectedRange(range)
            syncContent(from: textView)
        }

        private func textStyleTargetRange(
            in textView: NSTextView,
            textLength: Int
        ) -> NSRange {
            let activeSelection = clampedRange(textView.selectedRange(), textLength: textLength)
            if activeSelection.length > 0 {
                return activeSelection
            }

            let preservedSelection = clampedRange(parent.selectedRange, textLength: textLength)
            if preservedSelection.length > 0 {
                return preservedSelection
            }

            return NSRange(location: 0, length: textLength)
        }

        private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
            let requestedLocation = range.location == NSNotFound ? textLength : range.location
            let location = min(max(0, requestedLocation), textLength)
            let length = min(max(0, range.length), max(0, textLength - location))
            return NSRange(location: location, length: length)
        }

        func openImage(with imageID: UUID) {
            guard let image = imageMap[imageID] else { return }
            parent.onOpenImage(image)
        }

        fileprivate func applyImageCommand(
            _ command: NoteImageCommand,
            to imageID: UUID,
            in textView: ImagePasteTextView
        ) {
            guard var image = imageMap[imageID] else { return }

            switch command {
            case .originalSize:
                let size = Self.originalImageSize(for: image)
                image.width = size.width
                image.height = size.height
            case .fitWidth:
                let width = max(60, Double(textView.availableImageWidth))
                resize(&image, displayWidth: width)
            case .shrink:
                resize(&image, displayWidth: max(40, image.width * 0.85))
            case .grow:
                let originalWidth = Self.originalImageSize(for: image).width
                let maximumWidth = max(originalWidth, Double(textView.availableImageWidth))
                resize(&image, displayWidth: min(maximumWidth, image.width * 1.15))
            case let .align(alignment):
                image.alignment = alignment
            }

            let preservedHoverFrame = textView.hoverControlsFrame(for: imageID)
            imageMap[imageID] = image
            syncContent(from: textView)
            render(parent: parent, in: textView, preserveSelection: true)
            if let preservedHoverFrame {
                textView.showHoverControlsForImage(with: imageID, fixedFrame: preservedHoverFrame)
            } else {
                textView.showHoverControlsForImage(with: imageID)
            }
        }

        private func syncContent(from textView: ImagePasteTextView) {
            let content = extractContent(from: textView)
            let signature = parent.contentSignature(
                text: content.text,
                images: content.images,
                styleRuns: content.styleRuns
            )
            renderedSignature = signature
            imageMap = Dictionary(uniqueKeysWithValues: content.images.map { ($0.id, $0) })

            if parent.text != content.text {
                parent.text = content.text
            }
            if parent.images != content.images {
                parent.images = content.images
            }
            if parent.styleRuns != content.styleRuns {
                parent.styleRuns = content.styleRuns
            }
            parent.onContentChange(content.text, content.images, content.styleRuns)
        }

        private func extractContent(
            from textView: NSTextView
        ) -> (text: String, images: [NoteImage], styleRuns: [NoteTextStyleRun]) {
            guard let storage = textView.textStorage else {
                return (textView.string, [], [])
            }

            let string = storage.string as NSString
            var outputText = ""
            var outputImages: [NoteImage] = []
            var location = 0

            while location < storage.length {
                if let attachment = storage.attribute(
                    .attachment,
                    at: location,
                    effectiveRange: nil
                ) as? NoteImageTextAttachment {
                    if let image = imageMap[attachment.imageID] {
                        outputText.append(NoteModel.imagePlaceholder)
                        outputImages.append(image)
                    }
                    location += 1
                } else {
                    let characterRange = string.rangeOfComposedCharacterSequence(at: location)
                    outputText.append(string.substring(with: characterRange))
                    location = characterRange.upperBound
                }
            }

            let styleRuns = extractStyleRuns(from: storage)
            return (outputText, outputImages, styleRuns)
        }

        private func makeAttributedString(
            text: String,
            images: [NoteImage],
            styleRuns: [NoteTextStyleRun],
            attributes: [NSAttributedString.Key: Any]
        ) -> NSAttributedString {
            let attributedString = NSMutableAttributedString()
            var imageIndex = 0

            for character in text {
                if character == NoteModel.imagePlaceholderCharacter {
                    if imageIndex < images.count {
                        attributedString.append(Self.makeImageAttributedString(for: images[imageIndex]))
                        imageIndex += 1
                    }
                } else {
                    attributedString.append(
                        NSAttributedString(string: String(character), attributes: attributes)
                    )
                }
            }

            while imageIndex < images.count {
                if attributedString.length > 0 {
                    attributedString.append(NSAttributedString(string: "\n", attributes: attributes))
                }
                attributedString.append(Self.makeImageAttributedString(for: images[imageIndex]))
                imageIndex += 1
            }

            apply(styleRuns: styleRuns, to: attributedString)
            return attributedString
        }

        private func extractStyleRuns(from storage: NSTextStorage) -> [NoteTextStyleRun] {
            var styleRuns: [NoteTextStyleRun] = []
            storage.enumerateAttributes(
                in: NSRange(location: 0, length: storage.length),
                options: []
            ) { attributes, range, _ in
                guard attributes[.attachment] == nil,
                      let styleRun = styleRun(from: attributes, range: range)
                else { return }
                styleRuns.append(styleRun)
            }

            return NoteTextStyleRun.normalized(
                styleRuns,
                textLength: storage.length
            )
        }

        private func styleRun(
            from attributes: [NSAttributedString.Key: Any],
            range: NSRange
        ) -> NoteTextStyleRun? {
            let style = textStyle(from: attributes)
            let explicitFontSize: Double?
            if abs(style.fontSize - parent.fontSize) > 0.1 {
                explicitFontSize = style.fontSize
            } else {
                explicitFontSize = nil
            }

            let run = NoteTextStyleRun(
                location: range.location,
                length: range.length,
                bold: style.bold,
                italic: style.italic,
                underline: style.underline,
                strikethrough: style.strikethrough,
                fontSize: explicitFontSize
            )
            return run.hasVisibleStyle ? run : nil
        }

        private func apply(
            styleRuns: [NoteTextStyleRun],
            to attributedString: NSMutableAttributedString
        ) {
            let normalizedRuns = NoteTextStyleRun.normalized(
                styleRuns,
                textLength: attributedString.length
            )
            for run in normalizedRuns {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: Self.makeFont(
                        size: run.fontSize ?? parent.fontSize,
                        bold: run.bold,
                        italic: run.italic
                    ),
                ]
                if run.underline {
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if run.strikethrough {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                attributedString.addAttributes(
                    attributes,
                    range: NSRange(location: run.location, length: run.length)
                )
            }
        }

        private struct TextStyleState {
            var bold: Bool
            var italic: Bool
            var underline: Bool
            var strikethrough: Bool
            var fontSize: Double
        }

        private func textStyle(
            from attributes: [NSAttributedString.Key: Any]
        ) -> TextStyleState {
            let font = attributes[.font] as? NSFont
            let traits = font.map { NSFontManager.shared.traits(of: $0) } ?? []
            let underlineValue = attributes[.underlineStyle] as? Int ?? 0
            let strikethroughValue = attributes[.strikethroughStyle] as? Int ?? 0

            return TextStyleState(
                bold: traits.contains(.boldFontMask),
                italic: traits.contains(.italicFontMask),
                underline: underlineValue != 0,
                strikethrough: strikethroughValue != 0,
                fontSize: font.map { Double($0.pointSize) } ?? parent.fontSize
            )
        }

        private func targetState(
            for action: NoteTextStyleAction,
            in storage: NSTextStorage,
            range: NSRange
        ) -> Bool? {
            switch action {
            case .toggleBold, .toggleItalic, .toggleUnderline, .toggleStrikethrough:
                var foundUnstyledText = false
                storage.enumerateAttributes(in: range, options: []) { attributes, _, stop in
                    guard attributes[.attachment] == nil else { return }
                    let style = textStyle(from: attributes)
                    let isEnabled: Bool
                    switch action {
                    case .toggleBold:
                        isEnabled = style.bold
                    case .toggleItalic:
                        isEnabled = style.italic
                    case .toggleUnderline:
                        isEnabled = style.underline
                    case .toggleStrikethrough:
                        isEnabled = style.strikethrough
                    case .resetPlainText, .decreaseFontSize, .increaseFontSize:
                        isEnabled = false
                    }
                    if !isEnabled {
                        foundUnstyledText = true
                        stop.pointee = true
                    }
                }
                return foundUnstyledText
            case .resetPlainText, .decreaseFontSize, .increaseFontSize:
                return nil
            }
        }

        private func typingAttributes(
            byApplying action: NoteTextStyleAction,
            to attributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            let currentStyle = textStyle(from: attributes)
            let targetState: Bool?
            switch action {
            case .toggleBold:
                targetState = !currentStyle.bold
            case .toggleItalic:
                targetState = !currentStyle.italic
            case .toggleUnderline:
                targetState = !currentStyle.underline
            case .toggleStrikethrough:
                targetState = !currentStyle.strikethrough
            case .resetPlainText, .decreaseFontSize, .increaseFontSize:
                targetState = nil
            }
            return attributesByApplying(
                action: action,
                targetState: targetState,
                to: attributes
            )
        }

        private func attributesByApplying(
            action: NoteTextStyleAction,
            targetState: Bool?,
            to attributes: [NSAttributedString.Key: Any]
        ) -> [NSAttributedString.Key: Any] {
            var updatedAttributes = attributes
            var style = textStyle(from: attributes)

            switch action {
            case .toggleBold:
                style.bold = targetState ?? !style.bold
            case .toggleItalic:
                style.italic = targetState ?? !style.italic
            case .toggleUnderline:
                style.underline = targetState ?? !style.underline
            case .toggleStrikethrough:
                style.strikethrough = targetState ?? !style.strikethrough
            case .resetPlainText:
                style.bold = false
                style.italic = false
                style.underline = false
                style.strikethrough = false
                style.fontSize = parent.fontSize
            case .decreaseFontSize:
                style.fontSize = max(8, style.fontSize - 2)
            case .increaseFontSize:
                style.fontSize = min(72, style.fontSize + 2)
            }

            updatedAttributes[.font] = Self.makeFont(
                size: style.fontSize,
                bold: style.bold,
                italic: style.italic
            )
            if style.underline {
                updatedAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                updatedAttributes.removeValue(forKey: .underlineStyle)
            }
            if style.strikethrough {
                updatedAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                updatedAttributes.removeValue(forKey: .strikethroughStyle)
            }
            updatedAttributes[.foregroundColor] = parent.textColor
            return updatedAttributes
        }

        private static func makeFont(
            size: Double,
            bold: Bool,
            italic: Bool
        ) -> NSFont {
            let baseFont = NSFont.systemFont(
                ofSize: CGFloat(size),
                weight: bold ? .bold : .regular
            )
            guard italic else { return baseFont }
            return NSFontManager.shared.convert(
                baseFont,
                toHaveTrait: .italicFontMask
            )
        }

        private static func makeImageAttributedString(for image: NoteImage) -> NSAttributedString {
            let attributedString = NSMutableAttributedString(
                attachment: makeAttachment(for: image)
            )
            attributedString.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(for: image.alignment),
                range: NSRange(location: 0, length: attributedString.length)
            )
            return attributedString
        }

        private static func makeAttachment(for image: NoteImage) -> NSTextAttachment {
            let attachment = NoteImageTextAttachment(imageID: image.id)
            let displayImage = NSImage(data: image.data) ?? NSImage()
            displayImage.size = NSSize(width: image.width, height: image.height)
            attachment.image = displayImage
            attachment.bounds = NSRect(x: 0, y: -4, width: image.width, height: image.height)
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: displayImage)
            return attachment
        }

        private static func paragraphStyle(for alignment: NoteImageAlignment) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            switch alignment {
            case .left:
                style.alignment = .left
            case .center:
                style.alignment = .center
            case .right:
                style.alignment = .right
            }
            return style
        }

        private static func makeNoteImage(from image: NSImage) -> NoteImage? {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:])
            else { return nil }

            let originalWidth = Double(bitmap.pixelsWide)
            let originalHeight = Double(bitmap.pixelsHigh)
            guard originalWidth > 0, originalHeight > 0 else { return nil }

            let maxWidth = 220.0
            let maxHeight = 180.0
            let scale = min(1.0, maxWidth / originalWidth, maxHeight / originalHeight)
            return NoteImage(
                data: pngData,
                width: originalWidth * scale,
                height: originalHeight * scale,
                alignment: .left
            )
        }

        private static func originalImageSize(for image: NoteImage) -> CGSize {
            guard let bitmap = NSBitmapImageRep(data: image.data),
                  bitmap.pixelsWide > 0,
                  bitmap.pixelsHigh > 0
            else {
                return CGSize(
                    width: max(1, image.width),
                    height: max(1, image.height)
                )
            }
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        private func resize(_ image: inout NoteImage, displayWidth: Double) {
            let originalSize = Self.originalImageSize(for: image)
            guard originalSize.width > 0 else { return }
            image.width = displayWidth
            image.height = displayWidth * originalSize.height / originalSize.width
        }
    }
}

private final class NoteImageTextAttachment: NSTextAttachment {
    let imageID: UUID

    init(imageID: UUID) {
        self.imageID = imageID
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        self.imageID = UUID()
        super.init(coder: coder)
    }
}

private final class ImagePasteTextView: NSTextView {
    var onPasteImages: (([NSImage]) -> Void)?
    var onOpenImage: ((UUID) -> Void)?
    var onImageCommand: ((UUID, NoteImageCommand, ImagePasteTextView) -> Void)?
    private var hoverControls: ImageHoverControlsView?
    private var activeHoverImageRect: NSRect?
    private var trackingArea: NSTrackingArea?

    var availableImageWidth: CGFloat {
        let scrollWidth = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        return max(60, scrollWidth - textContainerInset.width * 2 - 8)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea

        super.updateTrackingAreas()
    }

    override func paste(_ sender: Any?) {
        let images = pastedImages()
        if !images.isEmpty {
            onPasteImages?(images)
            return
        }

        super.paste(sender)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hoverControls?.frame.contains(point) == true {
            super.mouseDown(with: event)
            return
        }

        if let imageID = imageHit(at: point)?.imageID {
            onOpenImage?(imageID)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hoverControls?.frame.insetBy(dx: -4, dy: -4).contains(point) == true {
            return
        }

        if let hit = imageHit(at: point) {
            showHoverControls(for: hit.imageID, imageRect: hit.rect)
        } else if activeHoverRegionContains(point) {
            return
        } else {
            hideHoverControls()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hideHoverControls()
    }

    func refreshHoverControls() {
        hoverControls?.removeFromSuperview()
        hoverControls = nil
        activeHoverImageRect = nil
    }

    func showHoverControlsForImage(with imageID: UUID) {
        guard let imageRect = imageRect(for: imageID) else { return }
        showHoverControls(for: imageID, imageRect: imageRect)
    }

    func showHoverControlsForImage(with imageID: UUID, fixedFrame: NSRect) {
        guard let imageRect = imageRect(for: imageID) else { return }
        let controls = ensureHoverControls(for: imageID)
        activeHoverImageRect = imageRect
        controls.frame = fixedFrame
        controls.isHidden = false
    }

    func hoverControlsFrame(for imageID: UUID) -> NSRect? {
        guard let hoverControls,
              !hoverControls.isHidden,
              hoverControls.imageID == imageID
        else { return nil }
        return hoverControls.frame
    }

    private func pastedImages() -> [NSImage] {
        let pasteboard = NSPasteboard.general
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        let fileImages = fileURLs.compactMap { NSImage(contentsOf: $0) }
        if !fileImages.isEmpty {
            return fileImages
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return [image]
        }

        return []
    }

    private func imageHit(at pointInView: CGPoint) -> (imageID: UUID, rect: NSRect)? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage
        else { return nil }

        var point = pointInView
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y

        guard point.x >= 0, point.y >= 0 else { return nil }

        let characterIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard characterIndex < textStorage.length,
              let attachment = textStorage.attribute(
                .attachment,
                at: characterIndex,
                effectiveRange: nil
              ) as? NoteImageTextAttachment
        else { return nil }

        guard let rect = imageRect(atCharacterIndex: characterIndex) else { return nil }
        return (attachment.imageID, rect)
    }

    private func imageRect(for imageID: UUID) -> NSRect? {
        guard let textStorage else { return nil }

        var result: NSRect?
        textStorage.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: textStorage.length),
            options: []
        ) { value, range, stop in
            guard let attachment = value as? NoteImageTextAttachment,
                  attachment.imageID == imageID
            else { return }
            result = imageRect(atCharacterIndex: range.location)
            stop.pointee = true
        }
        return result
    }

    private func imageRect(atCharacterIndex characterIndex: Int) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    private func showHoverControls(for imageID: UUID, imageRect: NSRect) {
        let controls = ensureHoverControls(for: imageID)
        activeHoverImageRect = imageRect
        let fittingSize = controls.fittingSize
        let centeredX = imageRect.midX - fittingSize.width / 2
        let x = min(max(4, centeredX), max(4, bounds.width - fittingSize.width - 4))
        let overlap = 2.0
        let preferredY: CGFloat
        let fallbackY: CGFloat
        if isFlipped {
            preferredY = imageRect.minY - fittingSize.height + overlap
            fallbackY = imageRect.maxY - overlap
        } else {
            preferredY = imageRect.maxY - overlap
            fallbackY = imageRect.minY - fittingSize.height + overlap
        }
        let maximumY = max(4, bounds.height - fittingSize.height - 4)
        let unclampedY = (preferredY >= 4 && preferredY <= maximumY) ? preferredY : fallbackY
        let y = min(max(4, unclampedY), max(4, bounds.height - fittingSize.height - 4))
        controls.frame = NSRect(origin: CGPoint(x: x, y: y), size: fittingSize)
        controls.isHidden = false
    }

    private func ensureHoverControls(for imageID: UUID) -> ImageHoverControlsView {
        if let existingControls = hoverControls {
            existingControls.imageID = imageID
            return existingControls
        }

        let controls = ImageHoverControlsView(imageID: imageID)
        controls.onCommand = { [weak self] imageID, command in
            guard let self else { return }
            self.onImageCommand?(imageID, command, self)
        }
        addSubview(controls)
        hoverControls = controls
        return controls
    }

    private func hideHoverControls() {
        hoverControls?.isHidden = true
        activeHoverImageRect = nil
    }

    private func activeHoverRegionContains(_ point: CGPoint) -> Bool {
        guard let activeHoverImageRect,
              let controls = hoverControls,
              !controls.isHidden
        else { return false }

        let hoverRegion = activeHoverImageRect
            .union(controls.frame)
            .insetBy(dx: -8, dy: -8)
        return hoverRegion.contains(point)
    }
}

private final class ImageHoverControlsView: NSVisualEffectView {
    var imageID: UUID
    var onCommand: ((UUID, NoteImageCommand) -> Void)?

    init(imageID: UUID) {
        self.imageID = imageID
        super.init(frame: .zero)

        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8

        let sizeRow = NSStackView(views: [
            button(title: "原圖", command: .originalSize),
            button(title: "貼齊", command: .fitWidth),
            resizeControl(),
        ])
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 4
        sizeRow.distribution = .fillEqually

        let alignmentRow = NSStackView(views: [
            button(title: "靠左", command: .align(.left)),
            button(title: "置中", command: .align(.center)),
            button(title: "靠右", command: .align(.right)),
        ])
        alignmentRow.orientation = .horizontal
        alignmentRow.spacing = 4
        alignmentRow.distribution = .fillEqually

        let stack = NSStackView(views: [sizeRow, alignmentRow])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 146),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    private func button(title: String, command: NoteImageCommand) -> NSButton {
        let button = ImageCommandButton(title: title, command: command)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = #selector(runCommand(_:))
        return button
    }

    private func resizeControl() -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ["-", "+"],
            trackingMode: .momentary,
            target: self,
            action: #selector(runResizeCommand(_:))
        )
        control.segmentStyle = .rounded
        control.setWidth(22, forSegment: 0)
        control.setWidth(22, forSegment: 1)
        control.toolTip = "縮小 / 放大"
        return control
    }

    @objc private func runCommand(_ sender: ImageCommandButton) {
        onCommand?(imageID, sender.command)
    }

    @objc private func runResizeCommand(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            onCommand?(imageID, .shrink)
        case 1:
            onCommand?(imageID, .grow)
        default:
            break
        }
    }
}

private final class ImageCommandButton: NSButton {
    let command: NoteImageCommand

    init(title: String, command: NoteImageCommand) {
        self.command = command
        super.init(frame: .zero)
        self.title = title
        setButtonType(.momentaryPushIn)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
