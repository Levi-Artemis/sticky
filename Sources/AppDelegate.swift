import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let noteManager = NoteManager()
    private var windowControllers: [UUID: NoteWindowController] = [:]
    private var statusItem: NSStatusItem?
    private var textCommandMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupTextCommandMonitor()
        setupMenuBar()
        applyDockVisibility()
        noteManager.load()

        if noteManager.notes.isEmpty {
            var note = noteManager.create()
            centerOnScreen(&note)
            noteManager.update(note)
            showWindow(for: note)
        } else {
            noteManager.notes.forEach { showWindow(for: $0) }
        }

        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowControllers.forEach { $0.value.savePosition() }
        noteManager.save()
    }

    // MARK: - Main Menu

    private func setupTextCommandMonitor() {
        textCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.handleTextCommand(event) else {
                return event
            }
            return nil
        }
    }

    private func handleTextCommand(_ event: NSEvent) -> Bool {
        guard let characters = event.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1
        else { return false }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let selector: Selector

        switch (characters, flags) {
        case ("x", .command):
            selector = #selector(NSText.cut(_:))
        case ("c", .command):
            selector = #selector(NSText.copy(_:))
        case ("v", .command):
            selector = #selector(NSText.paste(_:))
        case ("a", .command):
            selector = #selector(NSText.selectAll(_:))
        case ("z", .command):
            selector = Selector(("undo:"))
        case ("z", [.command, .shift]):
            selector = Selector(("redo:"))
        case ("v", [.command, .option, .shift]):
            selector = #selector(NSTextView.pasteAsPlainText(_:))
        default:
            return false
        }

        return NSApp.sendAction(selector, to: nil, from: self)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Sticky Notes",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ).target = NSApp
        appMenu.addItem(.separator())

        let servicesMenu = NSMenu()
        let servicesItem = NSMenuItem(
            title: "Services",
            action: nil,
            keyEquivalent: ""
        )
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide Sticky Notes",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ).target = NSApp

        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp

        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ).target = NSApp

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Sticky Notes",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ).target = NSApp

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let newNoteItem = fileMenu.addItem(
            withTitle: "New Note",
            action: #selector(createNote),
            keyEquivalent: "n"
        )
        newNoteItem.target = self
        fileMenu.addItem(.separator())

        let importDocumentItem = fileMenu.addItem(
            withTitle: "Import Sticky Notes Document...",
            action: #selector(importStickyNotesDocument),
            keyEquivalent: "i"
        )
        importDocumentItem.target = self

        let importMarkdownItem = fileMenu.addItem(
            withTitle: "Import Markdown...",
            action: #selector(importMarkdown),
            keyEquivalent: ""
        )
        importMarkdownItem.target = self

        fileMenu.addItem(.separator())

        let exportDocumentItem = fileMenu.addItem(
            withTitle: "Export Current Note...",
            action: #selector(exportCurrentNoteDocument),
            keyEquivalent: "e"
        )
        exportDocumentItem.target = self

        let exportAllDocumentItem = fileMenu.addItem(
            withTitle: "Export All Notes...",
            action: #selector(exportAllNotesDocument),
            keyEquivalent: ""
        )
        exportAllDocumentItem.target = self

        let exportMarkdownItem = fileMenu.addItem(
            withTitle: "Export Current Note as Markdown...",
            action: #selector(exportCurrentNoteMarkdown),
            keyEquivalent: ""
        )
        exportMarkdownItem.target = self

        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )

        let redoItem = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )

        let pasteAndMatchStyleItem = editMenu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatchStyleItem.keyEquivalentModifierMask = [.command, .option, .shift]

        editMenu.addItem(
            withTitle: "Delete",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )

        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.toolTip = "Sticky Notes"
            if let image = NSImage(
                systemSymbolName: "pin",
                accessibilityDescription: "Sticky Notes"
            ) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Notes"
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.delegate = self

        for note in noteManager.notes.reversed() {
            let trimmedText = note.text
                .replacingOccurrences(of: NoteModel.imagePlaceholder, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preview: String
            if trimmedText.isEmpty {
                preview = note.images.isEmpty ? "空白便利籤" : "圖片便利籤"
            } else {
                preview = String(trimmedText.prefix(30))
                    .replacingOccurrences(of: "\n", with: " ")
            }
            let item = NSMenuItem(
                title: preview,
                action: #selector(showNoteFromMenu(_:)),
                keyEquivalent: ""
            )
            item.representedObject = note.id.uuidString
            item.target = self
            menu.addItem(item)
        }

        if !noteManager.notes.isEmpty {
            menu.addItem(.separator())
        }

        let newItem = NSMenuItem(
            title: "新增便利籤",
            action: #selector(createNote),
            keyEquivalent: "n"
        )
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let importDocumentItem = NSMenuItem(
            title: "匯入 Sticky Notes 文件...",
            action: #selector(importStickyNotesDocument),
            keyEquivalent: ""
        )
        importDocumentItem.target = self
        menu.addItem(importDocumentItem)

        let importMarkdownItem = NSMenuItem(
            title: "匯入 Markdown...",
            action: #selector(importMarkdown),
            keyEquivalent: ""
        )
        importMarkdownItem.target = self
        menu.addItem(importMarkdownItem)

        let exportCurrentItem = NSMenuItem(
            title: "匯出目前便利籤...",
            action: #selector(exportCurrentNoteDocument),
            keyEquivalent: ""
        )
        exportCurrentItem.target = self
        menu.addItem(exportCurrentItem)

        let exportAllItem = NSMenuItem(
            title: "匯出全部便利籤...",
            action: #selector(exportAllNotesDocument),
            keyEquivalent: ""
        )
        exportAllItem.target = self
        menu.addItem(exportAllItem)

        let exportMarkdownItem = NSMenuItem(
            title: "匯出目前便利籤為 Markdown...",
            action: #selector(exportCurrentNoteMarkdown),
            keyEquivalent: ""
        )
        exportMarkdownItem.target = self
        menu.addItem(exportMarkdownItem)

        menu.addItem(.separator())

        let dockItem = NSMenuItem(
            title: hideFromDock ? "顯示 Dock 圖示" : "隱藏 Dock 圖示",
            action: #selector(toggleDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        menu.addItem(dockItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "離開 StickyNotes",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem?.menu {
            rebuildMenu()
        }
    }

    // MARK: - Actions

    @objc private func createNote() {
        var note = noteManager.create()
        centerOnScreen(&note)
        noteManager.update(note)
        showWindow(for: note)
        rebuildMenu()
    }

    @objc private func importStickyNotesDocument() {
        let panel = NSOpenPanel()
        panel.title = "Import Sticky Notes Document"
        panel.allowedContentTypes = [
            UTType(filenameExtension: NoteDocumentCodec.documentExtension) ?? .json,
            .json,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let notes = try NoteDocumentCodec.decodeDocument(data: data)
            importNotes(notes)
        } catch {
            showAlert(
                title: "匯入失敗",
                message: "無法讀取這個 Sticky Notes 文件。"
            )
        }
    }

    @objc private func importMarkdown() {
        let panel = NSOpenPanel()
        panel.title = "Import Markdown"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let note = try NoteDocumentCodec.readMarkdown(from: url)
            importNotes([note])
        } catch {
            showAlert(
                title: "匯入失敗",
                message: "無法讀取這個 Markdown 文件。"
            )
        }
    }

    @objc private func exportCurrentNoteDocument() {
        guard let note = activeNote() else {
            showNoActiveNoteAlert()
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Current Note"
        panel.allowedContentTypes = [
            UTType(filenameExtension: NoteDocumentCodec.documentExtension) ?? .json,
        ]
        panel.nameFieldStringValue = "Sticky Note.\(NoteDocumentCodec.documentExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try NoteDocumentCodec.encodeDocument(notes: [note])
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(
                title: "匯出失敗",
                message: "無法寫入 Sticky Notes 文件。"
            )
        }
    }

    @objc private func exportAllNotesDocument() {
        windowControllers.values.forEach { $0.savePosition() }
        guard !noteManager.notes.isEmpty else {
            showNoActiveNoteAlert()
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export All Notes"
        panel.allowedContentTypes = [
            UTType(filenameExtension: NoteDocumentCodec.documentExtension) ?? .json,
        ]
        panel.nameFieldStringValue = "Sticky Notes.\(NoteDocumentCodec.documentExtension)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try NoteDocumentCodec.encodeDocument(notes: noteManager.notes)
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(
                title: "匯出失敗",
                message: "無法寫入 Sticky Notes 文件。"
            )
        }
    }

    @objc private func exportCurrentNoteMarkdown() {
        guard let note = activeNote() else {
            showNoActiveNoteAlert()
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Current Note as Markdown"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
        ]
        panel.nameFieldStringValue = "Sticky Note.md"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try NoteDocumentCodec.writeMarkdown(note: note, to: url)
        } catch {
            showAlert(
                title: "匯出失敗",
                message: "無法寫入 Markdown 文件。"
            )
        }
    }

    private func activeNote() -> NoteModel? {
        guard let controller = activeNoteController() else { return nil }
        controller.savePosition()
        return controller.currentNote
    }

    private func activeNoteController() -> NoteWindowController? {
        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow,
           let controller = windowControllers.values.first(where: { $0.window === keyWindow })
        {
            return controller
        }

        return windowControllers.values.first
    }

    private func importNotes(_ notes: [NoteModel]) {
        for (index, note) in notes.enumerated() {
            var importedNote = note
            importedNote.id = UUID()
            let resizedLegacyImages = importedNote.normalizeLegacyImageDisplaySizes()
            let migratedImages = importedNote.ensureInlineImagePlaceholders()
            importedNote.styleRuns = NoteTextStyleRun.normalized(
                importedNote.styleRuns,
                textLength: (importedNote.text as NSString).length
            )
            centerOnScreen(&importedNote)
            let offset = Double(index) * 24
            importedNote.positionX += offset
            importedNote.positionY -= offset
            noteManager.add(importedNote)
            showWindow(for: importedNote)

            if resizedLegacyImages || migratedImages {
                noteManager.update(importedNote)
            }
        }
        rebuildMenu()
    }

    private func showNoActiveNoteAlert() {
        showAlert(
            title: "沒有可匯出的便利籤",
            message: "請先選取或開啟一張便利籤。"
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func centerOnScreen(_ note: inout NoteModel) {
        guard let screen = NSScreen.screens.first?.visibleFrame else { return }
        note.positionX = screen.midX - note.width / 2
        note.positionY = screen.midY - note.height / 2
    }

    @objc private func showNoteFromMenu(_ sender: NSMenuItem) {
        guard let uuidString = sender.representedObject as? String,
              let id = UUID(uuidString: uuidString)
        else { return }

        if let controller = windowControllers[id] {
            controller.window?.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let note = noteManager.notes.first(where: { $0.id == id })
        {
            showWindow(for: note)
        }
    }

    // MARK: - Dock Visibility

    private var hideFromDock: Bool {
        get { UserDefaults.standard.bool(forKey: "hideFromDock") }
        set { UserDefaults.standard.set(newValue, forKey: "hideFromDock") }
    }

    private func applyDockVisibility() {
        NSApp.setActivationPolicy(hideFromDock ? .accessory : .regular)
    }

    @objc private func toggleDock() {
        hideFromDock.toggle()
        applyDockVisibility()
        rebuildMenu()
    }

    // MARK: - Window Management

    private func showWindow(for note: NoteModel) {
        let controller = NoteWindowController(
            note: note,
            noteManager: noteManager,
            onClose: { [weak self] id in
                self?.windowControllers[id] = nil
                self?.rebuildMenu()
            },
            onChange: { [weak self] in
                self?.rebuildMenu()
            }
        )
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        windowControllers[note.id] = controller
    }
}
