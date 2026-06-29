import Cocoa
import SwiftUI

final class NoteWindowController: NSWindowController, NSWindowDelegate {

    private var note: NoteModel
    private unowned let noteManager: NoteManager
    private let onClose: (UUID) -> Void
    private let onChange: () -> Void

    init(
        note: NoteModel,
        noteManager: NoteManager,
        onClose: @escaping (UUID) -> Void,
        onChange: @escaping () -> Void
    ) {
        self.note = note
        self.noteManager = noteManager
        self.onClose = onClose
        self.onChange = onChange

        let rect = NSRect(
            x: note.positionX, y: note.positionY,
            width: max(note.width, 200), height: max(note.height, 200)
        )
        let window = NSWindow(
            contentRect: rect,
            styleMask: [
                .titled, .closable, .resizable, .fullSizeContentView,
                .miniaturizable,
            ],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = note.isPinned ? .floating : .normal
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 200, height: 200)

        super.init(window: window)
        window.delegate = self

        let hostingView = NSHostingView(
            rootView: NoteView(
                note: note,
                onUpdate: { [weak self] updatedNote in
                    guard let self = self else { return }
                    self.note = updatedNote
                    self.noteManager.update(updatedNote)
                    self.syncWindowLevel()
                    self.onChange()
                },
                onDelete: { [weak self] in
                    guard let self = self else { return }
                    self.noteManager.delete(note.id)
                    self.onClose(note.id)
                    self.close()
                }
            )
        )
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        savePosition()
    }

    func savePosition() {
        guard let window = window else { return }
        note.positionX = window.frame.origin.x
        note.positionY = window.frame.origin.y
        note.width = window.frame.width
        note.height = window.frame.height
        noteManager.update(note)
    }

    private func syncWindowLevel() {
        window?.level = note.isPinned ? .floating : .normal
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    func windowDidResize(_ notification: Notification) {
        savePosition()
    }

    func windowWillClose(_ notification: Notification) {
        savePosition()
        onClose(note.id)
    }
}
