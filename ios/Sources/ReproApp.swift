import SwiftGodotKit
import SwiftUI

// One GodotApp for the app's lifetime. The button (or `-autoToggle <n>`, every 2 s)
// removes GodotAppView from the SwiftUI tree and mounts a new one for the same GodotApp.
@main
struct ReproApp: App {
    let godotApp = GodotApp(packFile: "game.pck")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.godotApp, godotApp)
        }
    }
}

struct ContentView: View {
    @State private var showsGame = false
    @State private var toggles = 0

    var body: some View {
        VStack {
            Button(showsGame ? "Hide game" : "Show game", action: toggle)
                .buttonStyle(.borderedProminent)
            if showsGame {
                GodotAppView()
            } else {
                Color.gray.overlay { Text("Game view removed") }
            }
        }
        .task {
            let count = UserDefaults.standard.integer(forKey: "autoToggle")
            for _ in 0..<count {
                try? await Task.sleep(for: .seconds(2))
                toggle()
            }
            if count > 0 { NSLog("repro: finished %d toggles without crashing", count) }
        }
    }

    private func toggle() {
        showsGame.toggle()
        toggles += 1
        NSLog("repro: toggle %d, game view %@", toggles, showsGame ? "mounted" : "removed")
    }
}
