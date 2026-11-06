import SwiftUI

// MARK: - Mini Player Bar

struct PlayerBar: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: Library
    @State private var showExpanded = false

    var body: some View {
        if let song = player.current {
            VStack(spacing: 0) {
                // Mini Player Card
                HStack(spacing: 12) {
                    // Album art thumbnail
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: player.isPlaying ? "waveform" : "music.note")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.indigo.opacity(0.3), radius: 4, x: 0, y: 2)

                    // Song Info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.name)
                            .font(.system(.subheadline, design: .default).weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        Text(library.albumName(song.albumID) ?? "MyTracks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    // Quick Controls
                    HStack(spacing: 16) {
                        // Play / Pause
                        Button {
                            player.togglePlay()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)

                        // Skip to Next Song
                        Button {
                            player.skipToNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title3)
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip to next song")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    showExpanded = true
                }
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            if value.translation.width < -35 {
                                // Swipe left to skip to next song
                                player.skipToNext()
                            } else if value.translation.width > 35 {
                                // Swipe right for previous song
                                player.skipToPrevious()
                            }
                        }
                )

                // Thin playback progress bar at the bottom edge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(
                                width: max(
                                    0,
                                    min(
                                        geo.size.width * CGFloat(player.duration > 0 ? (player.time / player.duration) : 0),
                                        geo.size.width
                                    )
                                )
                            )
                    }
                }
                .frame(height: 2.5)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .sheet(isPresented: $showExpanded) {
                NowPlayingSheet(song: song)
                    .presentationDetents([.fraction(0.88), .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Full Screen / Expanded Now Playing Sheet

struct NowPlayingSheet: View {
    let song: Song
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var scrub = 0.0
    @State private var editing = false

    var body: some View {
        VStack(spacing: 24) {
            // Dismiss handle
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Spacer()

            // Large Album Artwork Card
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, Color.purple, Color.cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 260)
                    .shadow(color: Color.indigo.opacity(0.4), radius: 24, x: 0, y: 12)

                VStack(spacing: 12) {
                    Image(systemName: player.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 80, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            player.skipToNext()
                        } else if value.translation.width > 40 {
                            player.skipToPrevious()
                        }
                    }
            )

            // Song Info
            VStack(spacing: 6) {
                Text(player.current?.name ?? song.name)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Text(library.albumName((player.current ?? song).albumID) ?? "MyTracks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 24)

            // Scrubber Slider
            VStack(spacing: 6) {
                Slider(value: $scrub, in: 0...max(player.duration, 1)) { isEditing in
                    editing = isEditing
                    if !isEditing {
                        player.seek(scrub)
                    }
                }
                .tint(.accentColor)

                HStack {
                    Text(fmt(editing ? scrub : player.time))
                    Spacer()
                    let remaining = max(0, player.duration - (editing ? scrub : player.time))
                    Text("-" + fmt(remaining))
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 28)

            // Primary Playback Controls Deck
            HStack(spacing: 20) {
                // Shuffle
                Button {
                    player.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title3)
                        .foregroundColor(player.shuffle ? .accentColor : .secondary)
                }

                Spacer()

                // Previous Track
                Button {
                    player.skipToPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }

                // Skip 15s Backward
                Button {
                    player.skipBackward(by: 15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                // Play / Pause Circle
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.accentColor)
                }

                // Skip 15s Forward
                Button {
                    player.skipForward(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                // Skip to Next Track
                Button {
                    player.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
                .accessibilityLabel("Skip to next song")

                Spacer()

                // Loop / Repeat
                Button {
                    player.cycleLoop()
                } label: {
                    Image(systemName: player.loop == .one ? "repeat.1" : "repeat")
                        .font(.title3)
                        .foregroundColor(player.loop == .off ? .secondary : .accentColor)
                }
            }
            .padding(.horizontal, 24)

            // "Up Next" Queue Preview Card
            if let upNext = player.upNext {
                HStack(spacing: 12) {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.callout)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(upNext.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button {
                        player.skipToNext()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Skip")
                                .font(.footnote.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .padding(.bottom, 20)
        .onChange(of: player.time) { t in
            if !editing { scrub = t }
        }
    }

    private func fmt(_ t: Double) -> String {
        guard t.isFinite else { return "0:00" }
        let s = Int(t)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
