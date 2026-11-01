import Foundation

struct Song: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var fileName: String
    var albumID: UUID?
    var added = Date()
}

struct Album: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

private struct Store: Codable {
    var songs: [Song]
    var albums: [Album]
}

final class Library: ObservableObject {
    @Published var songs: [Song] = [] { didSet { save() } }
    @Published var albums: [Album] = [] { didSet { save() } }

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var dataURL: URL { docs.appendingPathComponent("library.json") }

    init() {
        if let data = try? Data(contentsOf: dataURL),
           let store = try? JSONDecoder().decode(Store.self, from: data) {
            songs = store.songs
            albums = store.albums
        }
    }

    private func save() {
        let store = Store(songs: songs, albums: albums)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: dataURL, options: .atomic)
        }
    }

    func fileURL(_ song: Song) -> URL { docs.appendingPathComponent(song.fileName) }

    func albumName(_ id: UUID?) -> String? {
        guard let id = id else { return nil }
        return albums.first { $0.id == id }?.name
    }

    // Songs
    func importFile(from url: URL, name: String, albumID: UUID?) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let stored = UUID().uuidString + ".mp3"
        try FileManager.default.copyItem(at: url, to: docs.appendingPathComponent(stored))
        songs.append(Song(name: name, fileName: stored, albumID: albumID))
    }

    func renameSong(_ id: UUID, to name: String) {
        if let i = songs.firstIndex(where: { $0.id == id }) { songs[i].name = name }
    }

    func move(_ id: UUID, to albumID: UUID?) {
        if let i = songs.firstIndex(where: { $0.id == id }) { songs[i].albumID = albumID }
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(at: fileURL(song))
        songs.removeAll { $0.id == song.id }
    }

    // Albums
    func addAlbum(_ name: String) {
        albums.append(Album(name: name))
    }

    func renameAlbum(_ id: UUID, to name: String) {
        if let i = albums.firstIndex(where: { $0.id == id }) { albums[i].name = name }
    }

    func deleteAlbum(_ id: UUID) {
        for i in songs.indices where songs[i].albumID == id { songs[i].albumID = nil }
        albums.removeAll { $0.id == id }
    }

    func assign(_ songIDs: Set<UUID>, to albumID: UUID) {
        for i in songs.indices where songIDs.contains(songs[i].id) { songs[i].albumID = albumID }
    }
}
