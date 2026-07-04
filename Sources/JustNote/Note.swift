import Foundation

struct Note: Identifiable, Equatable {
    let id: UUID
    var body: String
    var pinned: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        body: String = "",
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var title: String {
        Self.title(from: body)
    }

    var preview: String {
        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let text = lines.dropFirst().first ?? lines.first ?? "No text yet"
        return String(text.prefix(72))
    }

    var fileName: String {
        "\(id.uuidString).txt"
    }

    static func title(from body: String) -> String {
        let line = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let line, !line.isEmpty else { return "Untitled" }
        return String(line.prefix(48))
    }
}

struct NotesSnapshot: Equatable {
    var notes: [Note]
    var selectedNoteID: UUID?
    var recentNoteIDs: [UUID]
    var isFresh: Bool = false
}
