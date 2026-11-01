import SwiftUI

struct PlayerBar: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: Library
    @State private var scrub = 0.0
    @State private var editing = false

    var body: some View {
        if let song = player.current {
            VStack(spacing: 4) {
                Text(song.name).font(.headline).lineLimit(1)
                Slider(value: $scrub, in: 0...max(player.duration, 1)) { isEditing in
                    editing = isEditing
                    if !isEditing { player.seek(scrub) }
                }
                HStack {
                    Text(fmt(editing ? scrub : player.time))
                    Spacer()
                    Text(fmt(player.duration))
                }
                .font(.caption).foregroundColor(.secondary)

                HStack(spacing: 26) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle").font(.title3)
                            .foregroundColor(player.shuffle ? .accentColor : .secondary)
                    }
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title2) }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 46))
                    }
                    Button { player.advance(auto: false) } label: { Image(systemName: "forward.fill").font(.title2) }
                    Button { player.cycleLoop() } label: {
                        Image(systemName: player.loop == .one ? "repeat.1" : "repeat").font(.title3)
                            .foregroundColor(player.loop == .off ? .secondary : .accentColor)
                    }
                }
                .foregroundColor(.primary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .onChange(of: player.time) { t in if !editing { scrub = t } }
        }
    }

    private func fmt(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
