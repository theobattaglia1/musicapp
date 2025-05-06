import SwiftUI
import UniformTypeIdentifiers   // UTType.plainText for drag payloads

// ────────────────────────────────────────────────────────────
// MARK: – Artist page  (edit artwork • rename • playlists • collaborators)
// ────────────────────────────────────────────────────────────
struct ArtistDetailView: View {

    @EnvironmentObject private var store: ArtistStore
    @Environment(\.dismiss)       private var dismiss

    @State private var tab: Tab = .allSongs
    @State private var bannerPicker    = false
    @State private var avatarPicker    = false
    @State private var songArtPicker:  UUID?
    @State private var collaboratorSheet: String?
    @State private var showRename      = false
    @State private var draftName       = ""
    @State private var showAddSong     = false
    @State private var showAddPlaylist = false

    let artistID: UUID
    private var artist: Artist? { store.artists.first { $0.id == artistID } }

    enum Tab: String, CaseIterable, Identifiable {
        case allSongs, playlists, collaborators
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    // MARK: body
    var body: some View {
        if let artist { content(for: artist) } else { missing }
    }

    // ───────── main page
    private func content(for artist: Artist) -> some View {
        ScrollView {
            VStack(spacing: 0) {

                Header(artist: artist,
                       onBanner: { bannerPicker = true },
                       onAvatar: { avatarPicker = true },
                       onRename: {
                           draftName = artist.name
                           showRename = true
                       })

                Picker("Tab", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch tab {
                case .allSongs:
                    SongsList(artist: artist,
                              onArtTap: { songArtPicker = $0 })
                        .padding(.horizontal)

                case .playlists:
                    PlaylistsList(artist: artist, artistID: artistID)
                        .padding(.horizontal)

                case .collaborators:
                    CollaboratorsList(artist: artist,
                                      onTap: { collaboratorSheet = $0 })
                        .padding(.horizontal)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)

        // floating “＋”
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    tab == .playlists ? (showAddPlaylist = true)
                                      : (showAddSong     = true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .padding(22)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(radius: 6)
                }
                .padding(.trailing, 28)
                .padding(.bottom, 220)   // clears Now-Playing bar
            }
        }

        // MARK: sheets ----------------------------------------------------
        .sheet(isPresented: $bannerPicker) {
            ImagePicker(data: Binding(
                get: { artist.bannerData },
                set: { store.setBanner($0, for: artistID) }))
        }
        .sheet(isPresented: $avatarPicker) {
            ImagePicker(data: Binding(
                get: { artist.avatarData },
                set: { store.setAvatar($0, for: artistID) }))
        }
        .sheet(isPresented: $showAddSong) {
            AddSongSheet(artistID: artistID)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddPlaylistSheet(artistID: artistID)
                .environmentObject(store)
        }
        .sheet(item: $songArtPicker) { id in
            ImagePicker(data: Binding(
                get: { artist.songs.first { $0.id == id }?.artworkData },
                set: { store.setArtwork($0, for: id, artistID: artistID) }))
        }
        .sheet(item: $collaboratorSheet) { name in
            CollaboratorDetailView(name: name)
                .environmentObject(store)
        }
        .renameSheet(name: $draftName,
                     isPresented: $showRename,
                     onSave: { store.updateName($0, for: artistID) })
    }

    // ───────── fallback
    private var missing: some View {
        VStack {
            Spacer()
            Text("Artist not found").foregroundColor(.secondary)
            Spacer()
        }
        .onAppear { dismiss() }
    }
}

// ────────────────────────────────────────────────────────────
// MARK: Header  (banner • avatar • rename button)
// ────────────────────────────────────────────────────────────
private struct Header: View {
    let artist: Artist
    let onBanner: () -> Void
    let onAvatar: () -> Void
    let onRename: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            banner.resizable().scaledToFill()
                .frame(height: 260).clipped()
                .onTapGesture { onBanner() }

            HStack(spacing: 12) {
                avatar.resizable().scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle()).shadow(radius: 4)
                    .onTapGesture { onAvatar() }

                HStack(spacing: 4) {
                    Text(artist.name)
                        .font(.title).bold().foregroundColor(.white)
                        .shadow(radius: 3)
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                        .onTapGesture { onRename() }
                }
            }
            .padding([.leading, .bottom], 16)
        }
    }
    private var banner: Image {
        artist.bannerData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        ?? Image(systemName: "photo")
    }
    private var avatar: Image {
        artist.avatarData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
        ?? Image(systemName: "person.circle")
    }
}

// ────────────────────────────────────────────────────────────
// MARK: All Songs  (multi-select, swipe delete, batch edit)
// ────────────────────────────────────────────────────────────
private struct SongsList: View {
    let artist: Artist
    let onArtTap: (UUID) -> Void

    @EnvironmentObject private var store: ArtistStore
    @EnvironmentObject private var player: AudioPlayer

    @State private var selection  = Set<UUID>()
    @State private var editMode   : EditMode = .inactive
    @State private var batchSheet = false
    @State private var editSong   : Song?

    private let type = UTType.plainText

    var body: some View {
        List(selection: $selection) {
            ForEach(artist.chronologicalSongs) { song in
                HStack {
                    art(for: song)
                        .onTapGesture { onArtTap(song.id) }

                    VStack(alignment: .leading) {
                        Text(song.title)
                        Text(song.version)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editMode == .inactive {
                            player.playSong(song)
                        }
                    }
                }
                .contextMenu { Button("Edit") { editSong = song } }
                .onDrag { NSItemProvider(object: song.id.uuidString as NSString) }
            }
            .onDelete { idx in
                let ids = idx.map { artist.chronologicalSongs[$0].id }
                store.delete(songs: ids, for: artist.id)
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !selection.isEmpty { Button("Batch Edit") { batchSheet = true } }
                EditButton()
            }
        }
        .frame(maxHeight: .infinity)
        // sheets
        .sheet(isPresented: $batchSheet) {
            BatchEditSheet(artistID: artist.id,
                           songIDs: Array(selection))
                .environmentObject(store)
                .onDisappear { selection.removeAll() }
        }
        .sheet(item: $editSong) { s in
            EditSongSheet(artistID: artist.id, song: s)
                .environmentObject(store)
        }
    }

    private func art(for song: Song) -> some View {
        Group {
            if let d = song.artworkData, let i = UIImage(data: d) {
                Image(uiImage: i).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").resizable().scaledToFit()
                    .padding(10).foregroundColor(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// ────────────────────────────────────────────────────────────
// MARK: Playlists
// ────────────────────────────────────────────────────────────
private struct PlaylistsList: View {
    @EnvironmentObject private var store: ArtistStore
    @State           private var editMode: EditMode = .active
    let artist: Artist
    let artistID: UUID
    private let type = UTType.plainText

    var body: some View {
        List {
            ForEach(artist.playlists) { list in
                HStack {
                    Text(list.name)
                    Spacer()
                    Text("\(list.songIDs.count) tracks")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .onDrop(of: [type], isTargeted: nil, perform: drop(into: list))
            }
            .onMove { src, dst in
                store.movePlaylists(of: artistID, from: src, to: dst)
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .frame(maxHeight: .infinity)
    }

    private func drop(into list: Playlist) -> ([NSItemProvider]) -> Bool {
        { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: NSString.self) { item, _ in
                guard let s = item as? String,
                      let uuid = UUID(uuidString: s) else { return }
                DispatchQueue.main.async {
                    store.add(songID: uuid, to: list.id, for: artistID)
                }
            }
            return true
        }
    }
}

// ────────────────────────────────────────────────────────────
// MARK: Collaborators
// ────────────────────────────────────────────────────────────
private struct CollaboratorsList: View {
    let artist: Artist
    let onTap: (String) -> Void

    var body: some View {
        let names = Array(Set(artist.songs.flatMap { $0.creators })).sorted()

        if names.isEmpty {
            EmptyState(icon: "person.3",
                       title: "No Collaborators",
                       message: "Add song credits to see collaborators.")
        } else {
            ForEach(names, id: \.self) { name in
                HStack {
                    Text(name)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { onTap(name) }
                Divider()
            }
        }
    }
}

// ────────────────────────────────────────────────────────────
// MARK: Rename sheet modifier
// ────────────────────────────────────────────────────────────
private extension View {
    func renameSheet(name: Binding<String>,
                     isPresented: Binding<Bool>,
                     onSave: @escaping (String) -> Void) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                Form { TextField("Name", text: name) }
                    .navigationTitle("Rename Artist")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPresented.wrappedValue = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                onSave(name.wrappedValue)
                                isPresented.wrappedValue = false
                            }
                            .disabled(name.wrappedValue.isEmpty)
                        }
                    }
            }
        }
    }
}

// ────────────────────────────────────────────────────────────
// MARK: Empty-state helper
// ────────────────────────────────────────────────────────────
private struct EmptyState: View {
    let icon: String, title: String, message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
}
