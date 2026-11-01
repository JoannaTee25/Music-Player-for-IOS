import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        TabView {
            SongsView().tabItem { Label("Songs", systemImage: "music.note.list") }
            AlbumsView().tabItem { Label("Albums", systemImage: "square.stack") }
        }
    }
}

// MARK: - Songs tab

struct SongsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerManager
    @State private var showImporter = false

    var sorted: [Song] {
        library.songs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            SongList(songs: sorted, showAlbum: true,
                     emptyText: "No songs yet. Tap + to add MP3 files from your phone.")
                .navigationTitle("Songs")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if !sorted.isEmpty {
                            Button { player.play(songs: sorted, shuffle: true) } label: { Image(systemName: "shuffle") }
                        }
                        Button { showImporter = true } label: { Image(systemName: "plus") }
                    }
                }
                .modifier(ImportFlow(show: $showImporter, albumID: nil))
                .safeAreaInset(edge: .bottom) { PlayerBar() }
        }
    }
}

struct SongList: View {
    let songs: [Song]
    var showAlbum = true
    var emptyText = ""
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerManager
    @State private var renaming: Song?
    @State private var showRename = false
    @State private var newName = ""
    @State private var moving: Song?

    var body: some View {
        List {
            if songs.isEmpty { Text(emptyText).foregroundColor(.secondary) }
            ForEach(songs) { song in
                Button { player.play(songs: songs, start: song) } label: { row(song) }
                    .swipeActions {
                        Button(role: .destructive) { remove(song) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button { renaming = song; newName = song.name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                        Button { moving = song } label: { Label("Move to album", systemImage: "square.stack") }
                        Button(role: .destructive) { remove(song) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .alert("Rename song", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Save") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if let s = renaming, !n.isEmpty { library.renameSong(s.id, to: n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $moving) { AlbumPicker(song: $0) }
    }

    private func remove(_ song: Song) {
        player.remove(song.id)
        library.delete(song)
    }

    private func row(_ song: Song) -> some View {
        let isCurrent = player.currentID == song.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name).foregroundColor(isCurrent ? .accentColor : .primary)
                if showAlbum, let a = library.albumName(song.albumID) {
                    Text(a).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if isCurrent {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
}

struct AlbumPicker: View {
    let song: Song
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: Library

    var body: some View {
        NavigationStack {
            List {
                Button("No album") { library.move(song.id, to: nil); dismiss() }
                ForEach(library.albums) { a in
                    Button(a.name) { library.move(song.id, to: a.id); dismiss() }
                }
            }
            .navigationTitle("Move to album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Import (file picker + name prompt)

struct PendingFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ImportFlow: ViewModifier {
    @EnvironmentObject var library: Library
    @Binding var show: Bool
    var albumID: UUID?
    @State private var rest: [URL] = []
    @State private var currentFile: PendingFile?
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $show, allowedContentTypes: [.mp3, .audio],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    rest = urls
                    advance()
                }
            }
            .sheet(item: $currentFile) { file in
                NameSheet(url: file.url) { name in
                    do { try library.importFile(from: file.url, name: name, albumID: albumID) }
                    catch { errorText = error.localizedDescription }
                    advance()
                } onSkip: {
                    advance()
                }
            }
            .alert("Could not add song", isPresented: Binding(get: { errorText != nil },
                                                               set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
    }

    private func advance() {
        currentFile = rest.isEmpty ? nil : PendingFile(url: rest.removeFirst())
    }
}

struct NameSheet: View {
    let url: URL
    let onSave: (String) -> Void
    let onSkip: () -> Void
    @State private var name: String

    init(url: URL, onSave: @escaping (String) -> Void, onSkip: @escaping () -> Void) {
        self.url = url
        self.onSave = onSave
        self.onSkip = onSkip
        _name = State(initialValue: url.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song name") { TextField("Name", text: $name) }
                Section { Text(url.lastPathComponent).font(.footnote).foregroundColor(.secondary) }
            }
            .navigationTitle("Name this song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { onSkip() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(name.trimmingCharacters(in: .whitespaces)) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium])
    }
}

// MARK: - Albums tab

struct AlbumsView: View {
    @EnvironmentObject var library: Library
    @State private var showNew = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if library.albums.isEmpty {
                    Text("No albums yet. Tap + to create one.").foregroundColor(.secondary)
                }
                ForEach(library.albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { a in
                    NavigationLink(value: a) {
                        VStack(alignment: .leading) {
                            Text(a.name)
                            let n = library.songs.filter { $0.albumID == a.id }.count
                            Text("\(n) \(n == 1 ? "song" : "songs")").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let sorted = library.albums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    for i in idx { library.deleteAlbum(sorted[i].id) }
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(for: Album.self) { AlbumDetailView(albumID: $0.id) }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { newName = ""; showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("New album", isPresented: $showNew) {
                TextField("Album name", text: $newName)
                Button("Create") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { library.addAlbum(n) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .safeAreaInset(edge: .bottom) { PlayerBar() }
        }
    }
}

struct AlbumDetailView: View {
    let albumID: UUID
    @EnvironmentObject var library: Library
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var showAdd = false
    @State private var showRename = false
    @State private var showDelete = false
    @State private var name = ""

    var album: Album? { library.albums.first { $0.id == albumID } }
    var songs: [Song] {
        library.songs.filter { $0.albumID == albumID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !songs.isEmpty {
                HStack(spacing: 12) {
                    Button { player.play(songs: songs, shuffle: false) } label: {
                        Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { player.play(songs: songs, shuffle: true) } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                .padding()
            }
            SongList(songs: songs, showAlbum: false,
                     emptyText: "This album is empty. Use the menu at the top to add songs.")
        }
        .navigationTitle(album?.name ?? "")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showImporter = true } label: { Label("Upload songs here", systemImage: "square.and.arrow.down") }
                    Button { showAdd = true } label: { Label("Add from library", systemImage: "plus") }
                    Button { name = album?.name ?? ""; showRename = true } label: { Label("Rename album", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: { Label("Delete album", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .modifier(ImportFlow(show: $showImporter, albumID: albumID))
        .sheet(isPresented: $showAdd) { AddSongsSheet(albumID: albumID) }
        .alert("Rename album", isPresented: $showRename) {
            TextField("Album name", text: $name)
            Button("Save") {
                let n = name.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { library.renameAlbum(albumID, to: n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this album? Its songs stay in your library.", isPresented: $showDelete,
                            titleVisibility: .visible) {
            Button("Delete album", role: .destructive) {
                library.deleteAlbum(albumID)
                dismiss()
            }
        }
        .safeAreaInset(edge: .bottom) { PlayerBar() }
    }
}

struct AddSongsSheet: View {
    let albumID: UUID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: Library
    @State private var picked = Set<UUID>()

    var candidates: [Song] {
        library.songs.filter { $0.albumID != albumID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty { Text("Every song is already in this album.").foregroundColor(.secondary) }
                ForEach(candidates) { s in
                    Button {
                        if picked.contains(s.id) { picked.remove(s.id) } else { picked.insert(s.id) }
                    } label: {
                        HStack {
                            Text(s.name).foregroundColor(.primary)
                            Spacer()
                            if picked.contains(s.id) { Image(systemName: "checkmark").foregroundColor(.accentColor) }
                        }
                    }
                }
            }
            .navigationTitle("Add songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { library.assign(picked, to: albumID); dismiss() }
                }
            }
        }
    }
}
