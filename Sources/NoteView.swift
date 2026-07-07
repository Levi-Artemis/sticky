import AppKit
import SwiftUI

struct NoteView: View {
    @State private var note: NoteModel
    let onUpdate: (NoteModel) -> Void
    let onDelete: () -> Void

    @State private var text: String = ""
    @State private var evaluating = false
    @State private var needsMigrationSave: Bool
    @State private var previewWindowControllers: [UUID: ImagePreviewWindowController] = [:]
    @State private var editorSelectedRange = NSRange(location: 0, length: 0)
    @State private var lastNonEmptyEditorSelectedRange = NSRange(location: 0, length: 0)
    @State private var pendingStyleCommand: NoteTextStyleCommand?
    @State private var screenshotInProgress = false

    init(
        note: NoteModel,
        onUpdate: @escaping (NoteModel) -> Void,
        onDelete: @escaping () -> Void
    ) {
        var initialNote = note
        let resizedLegacyImages = initialNote.normalizeLegacyImageDisplaySizes()
        let migrated = initialNote.ensureInlineImagePlaceholders() || resizedLegacyImages
        self._note = State(initialValue: initialNote)
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._text = State(initialValue: initialNote.text)
        self._needsMigrationSave = State(initialValue: migrated)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editor
        }
        .background(note.color)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if needsMigrationSave {
                onUpdate(note)
                needsMigrationSave = false
            }
        }
    }

    private var toolbar: some View {
        GeometryReader { geometry in
            if geometry.size.width < 280 {
                compactToolbarContent
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                expandedToolbarContent
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(note.color.opacity(0.85))
    }

    private var expandedToolbarContent: some View {
        HStack(spacing: 12) {
            pinButton

            Spacer()

            Button {
                sendStyleAction(.toggleBold)
            } label: {
                Image(systemName: "bold")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("粗體")

            Button {
                sendStyleAction(.toggleItalic)
            } label: {
                Image(systemName: "italic")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("斜體")

            Button {
                sendStyleAction(.toggleUnderline)
            } label: {
                Image(systemName: "underline")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("底線")

            Button {
                sendStyleAction(.toggleStrikethrough)
            } label: {
                Image(systemName: "strikethrough")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("刪除線")

            Button {
                sendStyleAction(.resetPlainText)
            } label: {
                Image(systemName: "eraser")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("預設純文字")

            Button {
                sendStyleAction(.decreaseFontSize)
            } label: {
                Text("A")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("縮小字體")

            Button {
                sendStyleAction(.increaseFontSize)
            } label: {
                Text("A")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("放大字體")

            Button {
                captureScreenshot()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .disabled(screenshotInProgress)
            .help("截圖並插入")

            Button {
                note.nextColor()
                onUpdate(note)
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("變更顏色")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("刪除便利籤")
        }
    }

    private var compactToolbarContent: some View {
        HStack(spacing: 12) {
            pinButton

            Spacer()

            Menu {
                Button {
                    sendStyleAction(.toggleBold)
                } label: {
                    Label("粗體", systemImage: "bold")
                }

                Button {
                    sendStyleAction(.toggleItalic)
                } label: {
                    Label("斜體", systemImage: "italic")
                }

                Button {
                    sendStyleAction(.toggleUnderline)
                } label: {
                    Label("底線", systemImage: "underline")
                }

                Button {
                    sendStyleAction(.toggleStrikethrough)
                } label: {
                    Label("刪除線", systemImage: "strikethrough")
                }

                Button {
                    sendStyleAction(.resetPlainText)
                } label: {
                    Label("預設純文字", systemImage: "eraser")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .menuStyle(.borderlessButton)
            .help("文字格式")

            Button {
                sendStyleAction(.decreaseFontSize)
            } label: {
                Text("A")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("縮小字體")

            Button {
                sendStyleAction(.increaseFontSize)
            } label: {
                Text("A")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("放大字體")

            Button {
                captureScreenshot()
            } label: {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .disabled(screenshotInProgress)
            .help("截圖並插入")

            Button {
                note.nextColor()
                onUpdate(note)
            } label: {
                Image(systemName: "paintpalette")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("變更顏色")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("刪除便利籤")
        }
    }

    private var pinButton: some View {
        Button {
            note.isPinned.toggle()
            onUpdate(note)
        } label: {
            Image(systemName: note.isPinned ? "pin.fill" : "pin")
                .foregroundColor(note.isPinned ? .blue : adaptiveForegroundColor)
        }
        .buttonStyle(.plain)
        .help(note.isPinned ? "取消釘選" : "釘選在最上方")
    }

    private var editor: some View {
        PasteAwareTextEditor(
            text: $text,
            images: Binding(
                get: { note.images },
                set: { newImages in
                    note.images = newImages
                }
            ),
            styleRuns: Binding(
                get: { note.styleRuns },
                set: { newStyleRuns in
                    note.styleRuns = newStyleRuns
                }
            ),
            selectedRange: Binding(
                get: { editorSelectedRange },
                set: { newRange in
                    editorSelectedRange = newRange
                    if newRange.length > 0 {
                        lastNonEmptyEditorSelectedRange = newRange
                    }
                }
            ),
            pendingStyleCommand: $pendingStyleCommand,
            noteID: note.id,
            fontSize: note.fontSize,
            textColor: adaptiveNSForegroundColor,
            onContentChange: { newText, newImages, newStyleRuns in
                note.text = newText
                note.images = newImages
                note.styleRuns = newStyleRuns
                if text != newText {
                    text = newText
                }
                onUpdate(note)
            },
            onOpenImage: { image in
                openImagePreview(image)
            }
        )
            .background(note.color)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .onChange(of: text) { oldValue, newValue in
                guard !evaluating else { return }
                if newValue.count > oldValue.count, newValue.hasSuffix("="), newValue.count > 1 {
                    let lines = newValue.split(separator: "\n", omittingEmptySubsequences: false)
                    if var lastLine = lines.last, lastLine.hasSuffix("=") {
                        lastLine = lastLine.dropLast()
                        let expression = lastLine.trimmingCharacters(in: .whitespaces)
                        if let result = evaluateExpression(expression) {
                            evaluating = true
                            let formatted = formatResult(result)
                            var resultLines = lines.dropLast().map(String.init)
                            resultLines.append("\(expression) = \(formatted)")
                            text = resultLines.joined(separator: "\n")
                            note.text = text
                            note.styleRuns = NoteTextStyleRun.normalized(
                                note.styleRuns,
                                textLength: (text as NSString).length
                            )
                            onUpdate(note)
                            evaluating = false
                            return
                        }
                    }
                }
                note.text = newValue
                onUpdate(note)
            }
    }

    private func sendStyleAction(_ action: NoteTextStyleAction) {
        guard applyStyleActionToModel(action) else {
            postStyleActionToEditor(action)
            return
        }
    }

    @discardableResult
    private func applyStyleActionToModel(_ action: NoteTextStyleAction) -> Bool {
        let textLength = (text as NSString).length
        guard textLength > 0 else { return false }

        let targetRange = styleTargetRange(textLength: textLength)
        guard targetRange.length > 0 else { return false }

        note.styleRuns = updatedStyleRuns(
            applying: action,
            to: targetRange,
            in: note.styleRuns,
            textLength: textLength
        )
        onUpdate(note)
        return true
    }

    private func styleTargetRange(textLength: Int) -> NSRange {
        let activeRange = clampedRange(editorSelectedRange, textLength: textLength)
        if activeRange.length > 0 {
            return activeRange
        }

        let preservedRange = clampedRange(lastNonEmptyEditorSelectedRange, textLength: textLength)
        if preservedRange.length > 0 {
            return preservedRange
        }

        return NSRange(location: 0, length: textLength)
    }

    private func updatedStyleRuns(
        applying action: NoteTextStyleAction,
        to targetRange: NSRange,
        in styleRuns: [NoteTextStyleRun],
        textLength: Int
    ) -> [NoteTextStyleRun] {
        let normalizedRuns = NoteTextStyleRun.normalized(styleRuns, textLength: textLength)
        let breakpoints = styleBreakpoints(
            from: normalizedRuns,
            targetRange: targetRange,
            textLength: textLength
        )
        let targetEnd = targetRange.location + targetRange.length
        let targetEnabledState = toggleTargetState(
            for: action,
            targetRange: targetRange,
            breakpoints: breakpoints,
            styleRuns: normalizedRuns
        )

        var updatedRuns: [NoteTextStyleRun] = []
        for index in 0..<(breakpoints.count - 1) {
            let start = breakpoints[index]
            let end = breakpoints[index + 1]
            guard end > start else { continue }

            var style = effectiveStyle(at: start, in: normalizedRuns)
            if start >= targetRange.location, end <= targetEnd {
                style.apply(
                    action,
                    targetEnabledState: targetEnabledState,
                    defaultFontSize: note.fontSize
                )
            }

            if let run = style.noteTextStyleRun(
                location: start,
                length: end - start,
                defaultFontSize: note.fontSize
            ) {
                updatedRuns.append(run)
            }
        }

        return NoteTextStyleRun.normalized(updatedRuns, textLength: textLength)
    }

    private func styleBreakpoints(
        from styleRuns: [NoteTextStyleRun],
        targetRange: NSRange,
        textLength: Int
    ) -> [Int] {
        var breakpoints = Set([0, textLength])
        let targetEnd = targetRange.location + targetRange.length
        breakpoints.insert(min(max(0, targetRange.location), textLength))
        breakpoints.insert(min(max(0, targetEnd), textLength))

        for run in styleRuns {
            breakpoints.insert(min(max(0, run.location), textLength))
            breakpoints.insert(min(max(0, run.location + run.length), textLength))
        }

        return breakpoints.sorted()
    }

    private func toggleTargetState(
        for action: NoteTextStyleAction,
        targetRange: NSRange,
        breakpoints: [Int],
        styleRuns: [NoteTextStyleRun]
    ) -> Bool? {
        switch action {
        case .toggleBold, .toggleItalic, .toggleUnderline, .toggleStrikethrough:
            let targetEnd = targetRange.location + targetRange.length
            for index in 0..<(breakpoints.count - 1) {
                let start = breakpoints[index]
                let end = breakpoints[index + 1]
                guard start >= targetRange.location, end <= targetEnd else { continue }
                let style = effectiveStyle(at: start, in: styleRuns)
                switch action {
                case .toggleBold where !style.bold:
                    return true
                case .toggleItalic where !style.italic:
                    return true
                case .toggleUnderline where !style.underline:
                    return true
                case .toggleStrikethrough where !style.strikethrough:
                    return true
                default:
                    continue
                }
            }
            return false
        case .resetPlainText, .decreaseFontSize, .increaseFontSize:
            return nil
        }
    }

    private func effectiveStyle(
        at location: Int,
        in styleRuns: [NoteTextStyleRun]
    ) -> NoteTextStyleState {
        var style = NoteTextStyleState(fontSize: note.fontSize)
        for run in styleRuns where run.location <= location && location < run.location + run.length {
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

    private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let requestedLocation = range.location == NSNotFound ? textLength : range.location
        let location = min(max(0, requestedLocation), textLength)
        let length = min(max(0, range.length), max(0, textLength - location))
        return NSRange(location: location, length: length)
    }

    private func postStyleActionToEditor(_ action: NoteTextStyleAction) {
        NotificationCenter.default.post(
            name: .noteTextStyleCommand,
            object: nil,
            userInfo: [
                NoteTextStyleCommandUserInfo.noteID: note.id,
                NoteTextStyleCommandUserInfo.action: action,
            ]
        )
    }

    private func openImagePreview(_ image: NoteImage) {
        if let controller = previewWindowControllers[image.id] {
            controller.update(image: image)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = ImagePreviewWindowController(image: image) {
            previewWindowControllers[image.id] = nil
        }
        previewWindowControllers[image.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureScreenshot() {
        guard !screenshotInProgress else { return }
        screenshotInProgress = true

        let screenshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyNotes-Screenshot-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", screenshotURL.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                screenshotInProgress = false
                insertScreenshot(from: screenshotURL)
            }
        }

        do {
            try process.run()
        } catch {
            screenshotInProgress = false
            showScreenshotError("無法啟動截圖工具。")
        }
    }

    private func insertScreenshot(from url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return
        }

        guard let noteImage = makeNoteImage(fromPNGData: data) else {
            showScreenshotError("截圖完成，但圖片無法讀取。")
            return
        }

        insertInlineImage(noteImage)
    }

    private func insertInlineImage(_ noteImage: NoteImage) {
        let currentText = text
        let currentNSString = currentText as NSString
        let replacementRange = clampedRange(editorSelectedRange, in: currentNSString)
        let replacementEnd = replacementRange.location + replacementRange.length

        let prefix = currentNSString.substring(to: replacementRange.location)
        let selectedText = currentNSString.substring(with: replacementRange)
        let imageInsertIndex = imagePlaceholderCount(in: prefix)
        let selectedImageCount = imagePlaceholderCount(in: selectedText)

        var insertionText = ""
        if replacementRange.location > 0,
           currentNSString.substring(with: NSRange(location: replacementRange.location - 1, length: 1)) != "\n"
        {
            insertionText += "\n"
        }

        insertionText += NoteModel.imagePlaceholder

        if replacementEnd < currentNSString.length,
           currentNSString.substring(with: NSRange(location: replacementEnd, length: 1)) != "\n"
        {
            insertionText += "\n"
        }

        let mutableText = NSMutableString(string: currentText)
        mutableText.replaceCharacters(in: replacementRange, with: insertionText)

        var updatedImages = note.images
        let safeImageIndex = min(imageInsertIndex, updatedImages.count)
        let removalEnd = min(safeImageIndex + selectedImageCount, updatedImages.count)
        if safeImageIndex < removalEnd {
            updatedImages.removeSubrange(safeImageIndex..<removalEnd)
        }
        updatedImages.insert(noteImage, at: safeImageIndex)

        let newText = mutableText as String
        let newTextLength = (newText as NSString).length
        note.text = newText
        note.images = updatedImages
        note.styleRuns = NoteTextStyleRun.adjustedForReplacement(
            note.styleRuns,
            replacedRange: replacementRange,
            insertedLength: (insertionText as NSString).length,
            newTextLength: newTextLength
        )
        text = newText
        editorSelectedRange = NSRange(
            location: replacementRange.location + (insertionText as NSString).length,
            length: 0
        )
        onUpdate(note)
    }

    private func clampedRange(_ range: NSRange, in string: NSString) -> NSRange {
        let requestedLocation = range.location == NSNotFound ? string.length : range.location
        let location = min(max(0, requestedLocation), string.length)
        let length = min(max(0, range.length), string.length - location)
        return NSRange(location: location, length: length)
    }

    private func imagePlaceholderCount(in value: String) -> Int {
        value.reduce(0) { count, character in
            count + (character == NoteModel.imagePlaceholderCharacter ? 1 : 0)
        }
    }

    private func makeNoteImage(fromPNGData data: Data) -> NoteImage? {
        guard let bitmap = NSBitmapImageRep(data: data),
              bitmap.pixelsWide > 0,
              bitmap.pixelsHigh > 0
        else { return nil }

        let originalWidth = Double(bitmap.pixelsWide)
        let originalHeight = Double(bitmap.pixelsHigh)
        let scale = min(1.0, 220.0 / originalWidth, 180.0 / originalHeight)
        return NoteImage(
            data: data,
            width: originalWidth * scale,
            height: originalHeight * scale,
            alignment: .left
        )
    }

    private func showScreenshotError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "截圖失敗"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private var adaptiveForegroundColor: Color {
        isLightBackground ? .black : .white
    }

    private var adaptiveNSForegroundColor: NSColor {
        isLightBackground ? .black : .white
    }

    private var isLightBackground: Bool {
        guard let cgColor = note.color.cgColor,
              let rgb = cgColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!,
                intent: .defaultIntent,
                options: nil
              ),
              let components = rgb.components, components.count >= 3
        else { return true }
        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luminance > 0.5
    }

    private func evaluateExpression(_ expression: String) -> Double? {
        let expr = String(expression.filter { !$0.isWhitespace })
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "x", with: "*")
        guard !expr.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/")
        guard expr.rangeOfCharacter(from: allowed.inverted) == nil else { return nil }

        var tokens: [String] = []
        var current = ""
        for char in expr {
            if "+-*/".contains(char) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty else { return nil }

        var normalized: [String] = []
        var i = 0
        while i < tokens.count {
            if tokens[i] == "-", (i == 0 || ["+", "-", "*", "/"].contains(tokens[i - 1])) {
                guard i + 1 < tokens.count else { return nil }
                normalized.append("-" + tokens[i + 1])
                i += 2
            } else {
                normalized.append(tokens[i])
                i += 1
            }
        }

        var eval = normalized
        i = 0
        while i < eval.count {
            if eval[i] == "*" || eval[i] == "/" {
                guard i > 0, i + 1 < eval.count,
                      let left = Double(eval[i - 1]),
                      let right = Double(eval[i + 1])
                else { return nil }
                let result = eval[i] == "*" ? left * right : left / right
                guard result.isFinite else { return nil }
                eval[i - 1] = String(result)
                eval.remove(at: i)
                eval.remove(at: i)
            } else {
                i += 1
            }
        }

        guard let first = Double(eval[0]) else { return nil }
        var result = first
        i = 1
        while i < eval.count {
            guard i + 1 < eval.count, let right = Double(eval[i + 1]) else { return nil }
            switch eval[i] {
            case "+": result += right
            case "-": result -= right
            default: return nil
            }
            i += 2
        }
        return result
    }

    private func formatResult(_ result: Double) -> String {
        if floor(result) == result {
            return String(Int(result))
        }
        return String(format: "%.10g", result)
    }
}

private struct NoteTextStyleState {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var fontSize: Double

    mutating func apply(
        _ action: NoteTextStyleAction,
        targetEnabledState: Bool?,
        defaultFontSize: Double
    ) {
        switch action {
        case .toggleBold:
            bold = targetEnabledState ?? !bold
        case .toggleItalic:
            italic = targetEnabledState ?? !italic
        case .toggleUnderline:
            underline = targetEnabledState ?? !underline
        case .toggleStrikethrough:
            strikethrough = targetEnabledState ?? !strikethrough
        case .resetPlainText:
            bold = false
            italic = false
            underline = false
            strikethrough = false
            fontSize = defaultFontSize
        case .decreaseFontSize:
            fontSize = max(8, fontSize - 2)
        case .increaseFontSize:
            fontSize = min(72, fontSize + 2)
        }
    }

    func noteTextStyleRun(
        location: Int,
        length: Int,
        defaultFontSize: Double
    ) -> NoteTextStyleRun? {
        let explicitFontSize: Double?
        if abs(fontSize - defaultFontSize) > 0.1 {
            explicitFontSize = fontSize
        } else {
            explicitFontSize = nil
        }

        let run = NoteTextStyleRun(
            location: location,
            length: length,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough,
            fontSize: explicitFontSize
        )
        return run.hasVisibleStyle ? run : nil
    }
}
