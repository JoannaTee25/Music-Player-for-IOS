import SwiftUI

@main
struct MyTracksApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = PlayerManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .onAppear { player.library = library }
        }
    }
}
