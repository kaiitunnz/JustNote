import Foundation

enum NoteStoreError: LocalizedError {
    case missingSupportDirectory

    var errorDescription: String? {
        switch self {
        case .missingSupportDirectory:
            return "Could not locate Application Support."
        }
    }
}

final class NoteStore {
    let rootURL: URL
    private let notesURL: URL
    private let stateURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            guard let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw NoteStoreError.missingSupportDirectory
            }
            self.rootURL = supportURL.appendingPathComponent("JustNote", isDirectory: true)
        }
        notesURL = self.rootURL.appendingPathComponent("Notes", isDirectory: true)
        stateURL = self.rootURL.appendingPathComponent("state.json")
    }

    func load() throws -> NotesSnapshot {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return NotesSnapshot(notes: [], selectedNoteID: nil, recentNoteIDs: [])
        }
        let data = try Data(contentsOf: stateURL)
        let state = try JSONDecoder().decode(PersistedState.self, from: data)
        let notes = state.notes.map { metadata in
            let bodyURL = notesURL.appendingPathComponent(metadata.fileName)
            let body = (try? String(contentsOf: bodyURL, encoding: .utf8)) ?? ""
            return Note(
                id: metadata.id,
                body: body,
                pinned: metadata.pinned,
                createdAt: metadata.createdAt,
                updatedAt: metadata.updatedAt
            )
        }
        let noteIDs = Set(notes.map(\.id))
        return NotesSnapshot(
            notes: notes,
            selectedNoteID: state.selectedNoteID.flatMap { noteIDs.contains($0) ? $0 : nil },
            recentNoteIDs: state.recentNoteIDs.filter { noteIDs.contains($0) }
        )
    }

    func save(_ snapshot: NotesSnapshot) throws {
        try fileManager.createDirectory(at: notesURL, withIntermediateDirectories: true)
        let noteIDs = Set(snapshot.notes.map(\.id))
        let state = PersistedState(
            notes: snapshot.notes.map { NoteMetadata(note: $0) },
            selectedNoteID: snapshot.selectedNoteID.flatMap { noteIDs.contains($0) ? $0 : nil },
            recentNoteIDs: snapshot.recentNoteIDs.filter { noteIDs.contains($0) }
        )

        for note in snapshot.notes {
            let data = Data(note.body.utf8)
            try data.write(to: notesURL.appendingPathComponent(note.fileName), options: .atomic)
        }

        try removeDeletedNoteFiles(keeping: noteIDs)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func removeDeletedNoteFiles(keeping noteIDs: Set<UUID>) throws {
        guard fileManager.fileExists(atPath: notesURL.path) else { return }
        let files = try fileManager.contentsOfDirectory(
            at: notesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for file in files where file.pathExtension == "txt" {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if id.map({ !noteIDs.contains($0) }) ?? false {
                try fileManager.removeItem(at: file)
            }
        }
    }
}

private struct PersistedState: Codable {
    var notes: [NoteMetadata]
    var selectedNoteID: UUID?
    var recentNoteIDs: [UUID]
}

private struct NoteMetadata: Codable {
    var id: UUID
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(note: Note) {
        id = note.id
        pinned = note.pinned
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    var fileName: String {
        "\(id.uuidString).txt"
    }
}
