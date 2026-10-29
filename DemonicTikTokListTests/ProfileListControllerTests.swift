//
//  ProfileListControllerTests.swift
//  DemonicTikTokListTests
//

import Foundation
import SwiftData
import Testing
@testable import DemonicTikTokList

// MARK: - Testdoubles

/// Steuerbarer Zustand des Mock-Dienstes. Abrufe für „gesperrte“ Usernames warten,
/// bis der Test sie freigibt. So lassen sich verspätete Antworten gezielt nachstellen.
actor MockServiceState {
    private var metadata: [String: ProfileMetadata]
    private var gatedUsernames: Set<String>
    private var requestedUsernames: Set<String> = []
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var gateWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(metadata: [String: ProfileMetadata] = [:], gatedUsernames: Set<String> = []) {
        self.metadata = metadata
        self.gatedUsernames = gatedUsernames
    }

    func recordRequest(for username: String) {
        requestedUsernames.insert(username)
        requestWaiters[username]?.forEach { $0.resume() }
        requestWaiters[username] = nil
    }

    func waitUntilRequested(_ username: String) async {
        if requestedUsernames.contains(username) { return }
        await withCheckedContinuation { continuation in
            requestWaiters[username, default: []].append(continuation)
        }
    }

    func waitForRelease(of username: String) async {
        guard gatedUsernames.contains(username) else { return }
        await withCheckedContinuation { continuation in
            gateWaiters[username, default: []].append(continuation)
        }
    }

    func release(_ username: String) {
        gatedUsernames.remove(username)
        gateWaiters[username]?.forEach { $0.resume() }
        gateWaiters[username] = nil
    }

    func metadata(for username: String) -> ProfileMetadata {
        metadata[username] ?? ProfileMetadata()
    }
}

final class MockProfileService: TikTokProfileServicing {
    let state: MockServiceState
    let shortLinkTargets: [URL: URL]

    init(state: MockServiceState = MockServiceState(), shortLinkTargets: [URL: URL] = [:]) {
        self.state = state
        self.shortLinkTargets = shortLinkTargets
    }

    func resolveShortLink(_ url: URL) async throws -> URL {
        guard let target = shortLinkTargets[url] else { throw TikTokServiceError.network }
        return target
    }

    func fetchMetadata(for username: String) async -> ProfileMetadata {
        await state.recordRequest(for: username)
        await state.waitForRelease(of: username)
        return await state.metadata(for: username)
    }

    func downloadAvatar(from url: URL) async throws -> Data {
        Data("avatar:\(url.absoluteString)".utf8)
    }
}

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct ProfileListControllerTests {
    let container: ModelContainer
    let imageDirectory: URL

    init() throws {
        container = try ModelContainer(
            for: TikTokProfile.self,
            configurations: ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        )
        imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ControllerTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeController(service: MockProfileService = MockProfileService()) -> ProfileListController {
        ProfileListController(
            modelContext: container.mainContext,
            service: service,
            imageStore: ProfileImageStore(directory: imageDirectory),
            refreshesAutomatically: false
        )
    }

    private func link(_ username: String) -> ValidatedProfileLink {
        ValidatedProfileLink(username: username)
    }

    // MARK: Anlegen und Duplikate

    @Test func addsProfileWithCanonicalLink() throws {
        let controller = makeController()
        let validated = try #require(try? TikTokURLParser.parse("tiktok.com/@DemonLord?_t=abc"))
        guard case .profile(let username) = validated else {
            Issue.record("Profil erwartet")
            return
        }
        let profile = try controller.addProfile(link(username))
        #expect(profile.username == "demonlord")
        #expect(profile.profileURLString == "https://www.tiktok.com/@demonlord")
        #expect(profile.displayName == nil)
        #expect(controller.allProfiles().count == 1)
    }

    @Test func preventsDuplicateProfiles() async throws {
        let controller = makeController()
        try controller.addProfile(try await controller.resolveLink("https://www.tiktok.com/@demonlord?is_from_webapp=1"))
        let duplicate = try await controller.resolveLink("tiktok.com/@DemonLord#top")
        #expect(throws: TikTokLinkError.duplicate) {
            try controller.addProfile(duplicate)
        }
        #expect(controller.allProfiles().count == 1)
    }

    @Test func preventsEditingIntoExistingProfile() throws {
        let controller = makeController()
        try controller.addProfile(link("first"))
        let second = try controller.addProfile(link("second"))
        #expect(throws: TikTokLinkError.duplicate) {
            try controller.applyEdit(to: second.id, link: link("first"), manualDisplayName: nil, imageChange: .unchanged)
        }
        #expect(second.username == "second")
    }

    @Test func keepsStableOrderByCreationDate() throws {
        let controller = makeController()
        for name in ["c_user", "a_user", "b_user"] {
            try controller.addProfile(link(name))
        }
        #expect(controller.allProfiles().map(\.username) == ["c_user", "a_user", "b_user"])
    }

    // MARK: Kurzlinks

    @Test func resolvesShortLinksOnlyToProfiles() async throws {
        let profileShort = URL(string: "https://vm.tiktok.com/ZMprofile/")!
        let videoShort = URL(string: "https://vm.tiktok.com/ZMvideo/")!
        let foreignShort = URL(string: "https://vm.tiktok.com/ZMforeign/")!
        let service = MockProfileService(shortLinkTargets: [
            profileShort: URL(string: "https://www.tiktok.com/@demonlord?_t=xyz&_r=1")!,
            videoShort: URL(string: "https://www.tiktok.com/@demonlord/video/123?_r=1")!,
            foreignShort: URL(string: "https://tiktok.com.example.org/@demonlord")!
        ])
        let controller = makeController(service: service)

        #expect(try await controller.resolveLink("vm.tiktok.com/ZMprofile") == link("demonlord"))
        await #expect(throws: TikTokLinkError.shortLinkIsVideo) {
            try await controller.resolveLink("https://vm.tiktok.com/ZMvideo/")
        }
        await #expect(throws: TikTokLinkError.shortLinkNotProfile) {
            try await controller.resolveLink("https://vm.tiktok.com/ZMforeign/")
        }
        await #expect(throws: TikTokLinkError.shortLinkUnresolvable) {
            try await controller.resolveLink("https://vm.tiktok.com/ZMunknown/")
        }
    }

    // MARK: Metadaten

    @Test func refreshFillsAutomaticDataAndKeepsManualName() async throws {
        let state = MockServiceState(metadata: [
            "demonlord": ProfileMetadata(
                displayName: "Automatischer Name",
                avatarURL: URL(string: "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/a.jpeg")
            )
        ])
        let controller = makeController(service: MockProfileService(state: state))
        let profile = try controller.addProfile(link("demonlord"))
        try controller.applyEdit(to: profile.id, link: link("demonlord"), manualDisplayName: "Mein Name", imageChange: .unchanged)

        await controller.refreshMetadata(for: profile.id)

        #expect(profile.autoDisplayName == "Automatischer Name")
        #expect(profile.manualDisplayName == "Mein Name")
        #expect(profile.displayName == "Mein Name")
        #expect(profile.imageSource == .automatic)
        #expect(profile.localImageFileName != nil)
        #expect(profile.lastFetchedAt != nil)
        #expect(!controller.loadingProfileIDs.contains(profile.id))
    }

    @Test func refreshDoesNotOverwriteManualImage() async throws {
        let state = MockServiceState(metadata: [
            "demonlord": ProfileMetadata(avatarURL: URL(string: "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/a.jpeg"))
        ])
        let controller = makeController(service: MockProfileService(state: state))
        let profile = try controller.addProfile(link("demonlord"))
        try controller.applyEdit(
            to: profile.id,
            link: link("demonlord"),
            manualDisplayName: nil,
            imageChange: .setManual(Data("manuell".utf8))
        )
        let manualFile = profile.localImageFileName

        await controller.refreshMetadata(for: profile.id)

        #expect(profile.imageSource == .manual)
        #expect(profile.localImageFileName == manualFile)
        #expect(profile.remoteImageURLString != nil)
    }

    @Test func failedRefreshKeepsExistingData() async throws {
        let controller = makeController()
        let profile = try controller.addProfile(link("demonlord"))
        profile.autoDisplayName = "Gespeicherter Name"
        profile.remoteImageURLString = "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/a.jpeg"

        await controller.refreshMetadata(for: profile.id)

        #expect(profile.autoDisplayName == "Gespeicherter Name")
        #expect(profile.remoteImageURLString != nil)
        #expect(controller.incompleteProfileIDs.contains(profile.id))
    }

    @Test func refreshAllContinuesAfterIndividualFailures() async throws {
        let state = MockServiceState(metadata: [
            "first": ProfileMetadata(displayName: "Erster"),
            "third": ProfileMetadata(displayName: "Dritter")
        ])
        let controller = makeController(service: MockProfileService(state: state))
        let first = try controller.addProfile(link("first"))
        let second = try controller.addProfile(link("second"))
        let third = try controller.addProfile(link("third"))

        await controller.refreshAll()

        #expect(first.autoDisplayName == "Erster")
        #expect(second.autoDisplayName == nil)
        #expect(third.autoDisplayName == "Dritter")
        #expect(controller.loadingProfileIDs.isEmpty)
    }

    // MARK: Gleichzeitige Änderungen

    @Test func lateResultAfterUsernameChangeIsDiscarded() async throws {
        let state = MockServiceState(
            metadata: [
                "olduser": ProfileMetadata(
                    displayName: "Alter Name",
                    avatarURL: URL(string: "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/old.jpeg")
                )
            ],
            gatedUsernames: ["olduser"]
        )
        let controller = makeController(service: MockProfileService(state: state))
        let profile = try controller.addProfile(link("olduser"))
        let id = profile.id

        let refresh = Task { await controller.refreshMetadata(for: id) }
        await state.waitUntilRequested("olduser")

        try controller.applyEdit(to: id, link: link("newuser"), manualDisplayName: nil, imageChange: .unchanged)
        await state.release("olduser")
        await refresh.value

        let current = try #require(controller.profile(with: id))
        #expect(current.username == "newuser")
        #expect(current.profileURLString == "https://www.tiktok.com/@newuser")
        #expect(current.autoDisplayName == nil)
        #expect(current.remoteImageURLString == nil)
        #expect(current.localImageFileName == nil)
    }

    @Test func changingUsernameRemovesOldCustomizations() throws {
        let controller = makeController()
        let profile = try controller.addProfile(link("olduser"))
        profile.autoDisplayName = "Alter Auto-Name"
        try controller.applyEdit(
            to: profile.id,
            link: link("olduser"),
            manualDisplayName: "Alter manueller Name",
            imageChange: .setManual(Data("bild".utf8))
        )
        let oldFile = try #require(profile.localImageFileName)

        try controller.applyEdit(to: profile.id, link: link("newuser"), manualDisplayName: nil, imageChange: .unchanged)

        #expect(profile.username == "newuser")
        #expect(profile.displayName == nil)
        #expect(profile.localImageFileName == nil)
        #expect(profile.imageSource == nil)
        #expect(!controller.imageStore.fileExists(named: oldFile))
    }

    @Test func editingSameProfileKeepsCustomizations() throws {
        let controller = makeController()
        let profile = try controller.addProfile(link("demonlord"))
        try controller.applyEdit(
            to: profile.id,
            link: link("demonlord"),
            manualDisplayName: "Mein Name",
            imageChange: .setManual(Data("bild".utf8))
        )
        let file = profile.localImageFileName

        try controller.applyEdit(
            to: profile.id,
            link: try #require(try? TikTokURLParser.parse("tiktok.com/@DemonLord?lang=de")).profileLink,
            manualDisplayName: "Mein Name",
            imageChange: .unchanged
        )

        #expect(profile.manualDisplayName == "Mein Name")
        #expect(profile.localImageFileName == file)
        #expect(profile.imageSource == .manual)
    }

    @Test func resettingManualImageRemovesFile() throws {
        let controller = makeController()
        let profile = try controller.addProfile(link("demonlord"))
        try controller.applyEdit(to: profile.id, link: link("demonlord"), manualDisplayName: nil, imageChange: .setManual(Data("bild".utf8)))
        let file = try #require(profile.localImageFileName)

        try controller.applyEdit(to: profile.id, link: link("demonlord"), manualDisplayName: nil, imageChange: .resetManual)

        #expect(profile.localImageFileName == nil)
        #expect(profile.imageSource == nil)
        #expect(!controller.imageStore.fileExists(named: file))
    }

    // MARK: Löschen

    @Test func deleteRemovesProfileAndImage() throws {
        let controller = makeController()
        let profile = try controller.addProfile(link("demonlord"))
        try controller.applyEdit(to: profile.id, link: link("demonlord"), manualDisplayName: nil, imageChange: .setManual(Data("bild".utf8)))
        let file = try #require(profile.localImageFileName)

        try controller.deleteProfile(with: profile.id)

        #expect(controller.allProfiles().isEmpty)
        #expect(!controller.imageStore.fileExists(named: file))
    }

    @Test func lateResultAfterDeletionDoesNotRestoreProfile() async throws {
        let state = MockServiceState(
            metadata: ["demonlord": ProfileMetadata(
                displayName: "Name",
                avatarURL: URL(string: "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/a.jpeg")
            )],
            gatedUsernames: ["demonlord"]
        )
        let controller = makeController(service: MockProfileService(state: state))
        let profile = try controller.addProfile(link("demonlord"))
        let id = profile.id

        let refresh = Task { await controller.refreshMetadata(for: id) }
        await state.waitUntilRequested("demonlord")
        try controller.deleteProfile(with: id)
        await state.release("demonlord")
        await refresh.value

        #expect(controller.profile(with: id) == nil)
        #expect(controller.allProfiles().isEmpty)
        #expect(controller.loadingProfileIDs.isEmpty)
        let leftoverFiles = (try? FileManager.default.contentsOfDirectory(atPath: imageDirectory.path)) ?? []
        #expect(leftoverFiles.isEmpty)
    }
}

// MARK: - Dauerhafte Speicherung

@MainActor
struct PersistenceTests {
    @Test func profilesSurviveContainerRestart() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceTest-\(UUID().uuidString).store")
        let schema = Schema([TikTokProfile.self])
        let id: UUID

        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            let profile = TikTokProfile(username: "demonlord", profileURLString: "https://www.tiktok.com/@demonlord")
            profile.manualDisplayName = "Mein Name"
            profile.imageSource = .manual
            profile.localImageFileName = "bild.jpg"
            id = profile.id
            container.mainContext.insert(profile)
            try container.mainContext.save()
        }

        let reopened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<TikTokProfile>())
        let restored = try #require(profiles.first)
        #expect(profiles.count == 1)
        #expect(restored.id == id)
        #expect(restored.username == "demonlord")
        #expect(restored.profileURLString == "https://www.tiktok.com/@demonlord")
        #expect(restored.displayName == "Mein Name")
        #expect(restored.imageSource == .manual)
        #expect(restored.localImageFileName == "bild.jpg")
    }
}

private extension ParsedTikTokLink {
    var profileLink: ValidatedProfileLink {
        if case .profile(let username) = self {
            return ValidatedProfileLink(username: username)
        }
        return ValidatedProfileLink(username: "")
    }
}
