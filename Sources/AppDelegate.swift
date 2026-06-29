import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let noteManager = NoteManager()
    private var windowControllers: [UUID: NoteWindowController] = [:]
    private var statusItem: NSStatusItem?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowControllers.forEach { $0.value.savePosition() }
        noteManager.save()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Sticky Notes")
        image?.isTemplate = true
        statusItem?.button?.image = image

        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem = statusItem else { return }
        let menu = NSMenu()

        for note in noteManager.notes.reversed() {
            let preview = note.text.isEmpty
                ? "空白便利籤"
                : String(note.text.prefix(30))
                    .replacingOccurrences(of: "\n", with: " ")
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

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func createNote() {
        var note = noteManager.create()
        centerOnScreen(&note)
        noteManager.update(note)
        showWindow(for: note)
        rebuildMenu()
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
