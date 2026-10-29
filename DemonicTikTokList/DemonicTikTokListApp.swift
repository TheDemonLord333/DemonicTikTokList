//
//  DemonicTikTokListApp.swift
//  DemonicTikTokList
//

import SwiftData
import SwiftUI

@main
struct DemonicTikTokListApp: App {
    private let container: ModelContainer
    @State private var controller: ProfileListController

    init() {
        // UI-Tests starten mit einem leeren In-Memory-Speicher.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
        let container: ModelContainer
        do {
            let schema = Schema([TikTokProfile.self])
            let configuration = ModelConfiguration(
                "DemonicTikTokList",
                schema: schema,
                isStoredInMemoryOnly: isUITesting
            )
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Der lokale Speicher konnte nicht geöffnet werden: \(error)")
        }
        self.container = container

        let imageStore = isUITesting
            ? ProfileImageStore(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("UITestProfileImages", isDirectory: true))
            : ProfileImageStore()
        _controller = State(initialValue: ProfileListController(
            modelContext: container.mainContext,
            service: TikTokProfileService(),
            imageStore: imageStore
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .preferredColorScheme(.dark)
                .tint(Theme.blurple)
        }
        .modelContainer(container)
    }
}
