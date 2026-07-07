import Foundation

final class NoteManager {
    var notes: [NoteModel] = []

    private let savePath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("StickyNotes")
        try? FileManager.default.createDirectory(
            at: appDir, withIntermediateDirectories: true
        )
        return appDir.appendingPathComponent("notes.json")
    }()

    func load() {
        guard let data = try? Data(contentsOf: savePath),
              let decoded = try? JSONDecoder().decode(
                [NoteModel].self, from: data)
        else { return }
        notes = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: savePath, options: .atomic)
    }

    @discardableResult
    func create() -> NoteModel {
        let offset = Double(notes.count % 10) * 25.0
        let note = NoteModel(
            text: "",
            colorIndex: Int.random(in: 0..<NoteModel.colors.count),
            isPinned: false,
            positionX: 300 + offset,
            positionY: 300 - offset,
            width: 260,
            height: 260
        )
        notes.append(note)
        save()
        return note
    }

    @discardableResult
    func add(_ note: NoteModel) -> NoteModel {
        notes.append(note)
        save()
        return note
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func update(_ note: NoteModel) {
        guard let index = notes.firstIndex(where: { $0.id == note.id })
        else { return }
        notes[index] = note
        save()
    }
}
