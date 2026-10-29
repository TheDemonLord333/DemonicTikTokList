//
//  PreviewSupport.swift
//  DemonicTikTokList
//

#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Beispieldaten ausschließlich für SwiftUI-Previews. Es finden keine Netzwerkzugriffe statt.
enum PreviewSupport {
    static func makeRoot(withSamples: Bool) -> some View {
        let container = makeContainer(withSamples: withSamples)
        let controller = makeController(for: container)
        return ContentView()
            .environment(controller)
            .modelContainer(container)
            .preferredColorScheme(.dark)
            .tint(Theme.blurple)
    }

    static func makeContainer(withSamples: Bool) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: TikTokProfile.self, configurations: configuration) else {
            fatalError("Preview-Container konnte nicht erstellt werden.")
        }
        if withSamples {
            let samples: [(String, String?)] = [
                ("demonlord", "The Demon Lord"),
                ("nightcrawler.666", nil),
                ("green_flame", "Grüne Flamme")
            ]
            for (index, sample) in samples.enumerated() {
                let profile = TikTokProfile(
                    username: sample.0,
                    profileURLString: TikTokURLParser.canonicalProfileURLString(for: sample.0),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
                profile.autoDisplayName = sample.1
                container.mainContext.insert(profile)
            }
        }
        return container
    }

    static func makeController(for container: ModelContainer) -> ProfileListController {
        ProfileListController(
            modelContext: container.mainContext,
            service: PreviewProfileService(),
            imageStore: ProfileImageStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PreviewProfileImages", isDirectory: true)
            ),
            refreshesAutomatically: false
        )
    }
}

/// Liefert in Previews keine Daten und greift nie auf das Netzwerk zu.
nonisolated struct PreviewProfileService: TikTokProfileServicing {
    func resolveShortLink(_ url: URL) async throws -> URL {
        throw TikTokServiceError.network
    }

    func fetchMetadata(for username: String) async -> ProfileMetadata {
        ProfileMetadata()
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        throw TikTokServiceError.network
    }
}
#endif
