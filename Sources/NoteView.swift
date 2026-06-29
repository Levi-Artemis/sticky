import SwiftUI

struct NoteView: View {
    @State private var note: NoteModel
    let onUpdate: (NoteModel) -> Void
    let onDelete: () -> Void

    @State private var text: String = ""
    @State private var evaluating = false

    init(
        note: NoteModel,
        onUpdate: @escaping (NoteModel) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self._note = State(initialValue: note)
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._text = State(initialValue: note.text)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            editor
        }
        .background(note.color)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                note.isPinned.toggle()
                onUpdate(note)
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .foregroundColor(note.isPinned ? .blue : adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help(note.isPinned ? "取消釘選" : "釘選在最上方")

            Spacer()

            Button {
                note.fontSize = max(8, note.fontSize - 2)
                onUpdate(note)
            } label: {
                Text("A")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("縮小字體")

            Button {
                note.fontSize = min(48, note.fontSize + 2)
                onUpdate(note)
            } label: {
                Text("A")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(adaptiveForegroundColor)
            }
            .buttonStyle(.plain)
            .help("放大字體")

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
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .background(note.color.opacity(0.85))
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: note.fontSize))
            .foregroundColor(adaptiveForegroundColor)
            .scrollContentBackground(.hidden)
            .background(note.color)
            .scrollIndicators(.hidden)
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

    private var adaptiveForegroundColor: Color {
        guard let cgColor = note.color.cgColor,
              let rgb = cgColor.converted(
                to: CGColorSpace(name: CGColorSpace.sRGB)!,
                intent: .defaultIntent,
                options: nil
              ),
              let components = rgb.components, components.count >= 3
        else { return .black }
        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luminance > 0.5 ? .black : .white
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
