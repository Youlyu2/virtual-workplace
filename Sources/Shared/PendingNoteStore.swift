import Foundation

/// Independent durable storage: task-source changes and heartbeats do not
/// rewrite a user's notes. Invalid reads never replace the original file.
struct PendingNoteStore {
    let url: URL
    static let maximumFileSize = 131_072

    init(url: URL) { self.url = url }

    func read() throws -> [PendingNote] {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumFileSize else { throw PendingNoteError.fileTooLarge }
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumFileSize else { throw PendingNoteError.fileTooLarge }
            let notes = try JSONDecoder().decode([PendingNote].self, from: data)
            try PendingNote.validate(notes)
            return notes
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            return []
        }
    }

    func write(_ notes: [PendingNote]) throws {
        try PendingNote.validate(notes)
        let data = try JSONEncoder().encode(notes)
        guard data.count <= Self.maximumFileSize else { throw PendingNoteError.fileTooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
