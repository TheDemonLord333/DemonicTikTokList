//
//  ProfileListController.swift
//  DemonicTikTokList
//

import Foundation
import Observation
import SwiftData

/// Änderung am Profilbild im Bearbeitungsformular.
enum ProfileImageChange: Equatable {
    case unchanged
    case setManual(Data)
    case resetManual
}

nonisolated enum ProfileStoreError: LocalizedError, Equatable {
    case profileMissing
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            return "Das Profil ist nicht mehr vorhanden."
        case .saveFailed:
            return "Die Änderungen konnten nicht gespeichert werden."
        }
    }
}

/// Verwaltet Anlegen, Bearbeiten, Löschen und Aktualisieren der gespeicherten Profile.
///
/// Alle SwiftData- und UI-Änderungen laufen auf dem MainActor. Jeder Metadatenabruf erhält
/// ein Token; verspätete Antworten werden verworfen, wenn das Profil inzwischen gelöscht,
/// auf einen anderen Username geändert oder erneut abgefragt wurde.
@MainActor
@Observable
final class ProfileListController {
    static let maxConcurrentRefreshes = 3

    let modelContext: ModelContext
    let service: any TikTokProfileServicing
    let imageStore: ProfileImageStore
    /// Startet nach Anlegen oder Linkänderung automatisch einen Abruf. In Tests abschaltbar.
    let refreshesAutomatically: Bool
    @ObservationIgnored private var fetchTokens: [UUID: UUID] = [:]
    @ObservationIgnored private var didRunLaunchMaintenance = false

    /// Profile, deren Metadaten gerade geladen werden.
    private(set) var loadingProfileIDs: Set<UUID> = []
    /// Profile, bei denen der letzte Abruf nicht alle Daten liefern konnte.
    private(set) var incompleteProfileIDs: Set<UUID> = []

    init(
        modelContext: ModelContext,
        service: any TikTokProfileServicing,
        imageStore: ProfileImageStore,
        refreshesAutomatically: Bool = true
    ) {
        self.modelContext = modelContext
        self.service = service
        self.imageStore = imageStore
        self.refreshesAutomatically = refreshesAutomatically
    }

    // MARK: - Abfragen

    func profile(with id: UUID) -> TikTokProfile? {
        let targetID = id
        var descriptor = FetchDescriptor<TikTokProfile>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let profile = try? modelContext.fetch(descriptor).first, !profile.isDeleted else { return nil }
        return profile
    }

    func allProfiles() -> [TikTokProfile] {
        let descriptor = FetchDescriptor<TikTokProfile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func existingUsernames(excluding excludedID: UUID? = nil) -> [String] {
        allProfiles()
            .filter { $0.id != excludedID }
            .map(\.username)
    }

    // MARK: - Linkprüfung

    /// Prüft den eingegebenen Link und löst Kurzlinks auf. Akzeptiert nur echte Profilziele.
    func resolveLink(_ input: String) async throws -> ValidatedProfileLink {
        switch try TikTokURLParser.parse(input) {
        case .profile(let username):
            return ValidatedProfileLink(username: username)
        case .shortLink(let shortURL):
            let finalURL: URL
            do {
                finalURL = try await service.resolveShortLink(shortURL)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TikTokLinkError.shortLinkUnresolvable
            }
            do {
                if case .profile(let username) = try TikTokURLParser.parse(finalURL.absoluteString) {
                    return ValidatedProfileLink(username: username)
                }
            } catch TikTokLinkError.videoLink {
                throw TikTokLinkError.shortLinkIsVideo
            } catch {
                // Andere Ziele werden unten einheitlich abgelehnt.
            }
            throw TikTokLinkError.shortLinkNotProfile
        }
    }

    // MARK: - Anlegen

    @discardableResult
    func addProfile(_ link: ValidatedProfileLink) throws -> TikTokProfile {
        guard !ProfileDuplicateDetector.isDuplicate(username: link.username, existingUsernames: existingUsernames()) else {
            throw TikTokLinkError.duplicate
        }
        let profile = TikTokProfile(username: link.username, profileURLString: link.canonicalURLString)
        modelContext.insert(profile)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ProfileStoreError.saveFailed
        }
        scheduleRefresh(for: profile.id)
        return profile
    }

    // MARK: - Bearbeiten

    /// Übernimmt die Änderungen aus dem Bearbeitungsformular.
    ///
    /// Führt der Link zu einem anderen Username, werden alle Daten des bisherigen Profils
    /// inklusive manueller Anpassungen entfernt. `manualDisplayName` und `imageChange`
    /// beziehen sich dann bereits auf das neue Profil.
    func applyEdit(
        to profileID: UUID,
        link: ValidatedProfileLink,
        manualDisplayName: String?,
        imageChange: ProfileImageChange
    ) throws {
        guard let profile = profile(with: profileID) else { throw ProfileStoreError.profileMissing }
        guard !ProfileDuplicateDetector.isDuplicate(
            username: link.username,
            existingUsernames: existingUsernames(excluding: profileID)
        ) else {
            throw TikTokLinkError.duplicate
        }

        var filesToDeleteAfterSave: [String] = []
        var newlyWrittenFile: String?
        var needsRefresh = false

        if profile.username != link.username {
            // Laufende Abrufe des alten Profils dürfen nichts mehr zurückschreiben.
            invalidateFetch(for: profileID)
            incompleteProfileIDs.remove(profileID)
            if let oldFile = profile.localImageFileName {
                filesToDeleteAfterSave.append(oldFile)
            }
            profile.username = link.username
            profile.autoDisplayName = nil
            profile.manualDisplayName = nil
            profile.remoteImageURLString = nil
            profile.localImageFileName = nil
            profile.imageSource = nil
            profile.lastFetchedAt = nil
            needsRefresh = true
        }
        profile.profileURLString = link.canonicalURLString
        profile.manualDisplayName = Self.normalizedManualName(manualDisplayName)

        switch imageChange {
        case .unchanged:
            break
        case .setManual(let data):
            let fileName: String
            do {
                fileName = try imageStore.save(data)
            } catch {
                modelContext.rollback()
                throw ProfileStoreError.saveFailed
            }
            newlyWrittenFile = fileName
            if let oldFile = profile.localImageFileName {
                filesToDeleteAfterSave.append(oldFile)
            }
            profile.localImageFileName = fileName
            profile.imageSource = .manual
        case .resetManual:
            if profile.imageSource == .manual {
                if let oldFile = profile.localImageFileName {
                    filesToDeleteAfterSave.append(oldFile)
                }
                profile.localImageFileName = nil
                profile.imageSource = nil
                needsRefresh = true
            }
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            imageStore.delete(named: newlyWrittenFile)
            throw ProfileStoreError.saveFailed
        }
        filesToDeleteAfterSave.forEach { imageStore.delete(named: $0) }
        updateCompleteness(of: profile)

        if needsRefresh {
            scheduleRefresh(for: profileID)
        }
    }

    // MARK: - Löschen

    func deleteProfile(with profileID: UUID) throws {
        guard let profile = profile(with: profileID) else { return }
        let fileName = profile.localImageFileName
        invalidateFetch(for: profileID)
        incompleteProfileIDs.remove(profileID)
        modelContext.delete(profile)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw ProfileStoreError.saveFailed
        }
        imageStore.delete(named: fileName)
    }

    // MARK: - Aktualisieren

    /// Aktualisiert die automatischen Daten aller Profile mit begrenzter Parallelität.
    /// Fehler einzelner Profile brechen die Aktualisierung nicht ab.
    func refreshAll() async {
        await refresh(profileIDs: allProfiles().map(\.id))
    }

    func refresh(profileIDs: [UUID]) async {
        guard !profileIDs.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = profileIDs.makeIterator()
            for _ in 0..<min(Self.maxConcurrentRefreshes, profileIDs.count) {
                if let id = iterator.next() {
                    group.addTask { await self.refreshMetadata(for: id) }
                }
            }
            while await group.next() != nil {
                if let id = iterator.next() {
                    group.addTask { await self.refreshMetadata(for: id) }
                }
            }
        }
    }

    /// Lädt die automatischen Daten eines Profils. Vorhandene Daten bleiben bei Fehlern erhalten.
    func refreshMetadata(for profileID: UUID) async {
        guard let profile = profile(with: profileID) else { return }
        let username = profile.username
        let token = UUID()
        fetchTokens[profileID] = token
        loadingProfileIDs.insert(profileID)
        defer {
            if fetchTokens[profileID] == token {
                fetchTokens[profileID] = nil
                loadingProfileIDs.remove(profileID)
            }
        }

        let metadata = await service.fetchMetadata(for: username)

        var avatarData: Data?
        if let avatarURL = metadata.avatarURL, isFetchCurrent(profileID: profileID, token: token, username: username),
           self.profile(with: profileID)?.imageSource != .manual {
            avatarData = try? await service.downloadAvatar(from: avatarURL)
        }

        // Nach jedem `await` erneut prüfen: Das Profil kann gelöscht oder geändert worden sein.
        guard isFetchCurrent(profileID: profileID, token: token, username: username),
              let current = self.profile(with: profileID) else {
            return
        }

        var fileToDelete: String?
        var newFile: String?
        if let displayName = metadata.displayName {
            current.autoDisplayName = displayName
        }
        if let avatarURL = metadata.avatarURL {
            current.remoteImageURLString = avatarURL.absoluteString
        }
        if let avatarData, current.imageSource != .manual, let fileName = try? imageStore.save(avatarData) {
            fileToDelete = current.localImageFileName
            newFile = fileName
            current.localImageFileName = fileName
            current.imageSource = .automatic
        }
        if metadata.displayName != nil || newFile != nil {
            current.lastFetchedAt = .now
        }

        do {
            try modelContext.save()
            imageStore.delete(named: fileToDelete)
        } catch {
            modelContext.rollback()
            imageStore.delete(named: newFile)
        }
        updateCompleteness(of: current, fetchedName: metadata.displayName != nil)
    }

    /// Einmal pro App-Start: verwaiste Bilddateien entfernen und Profile ohne Daten nachladen.
    func performLaunchMaintenance() async {
        guard !didRunLaunchMaintenance else { return }
        didRunLaunchMaintenance = true
        let profiles = allProfiles()
        imageStore.removeOrphanedFiles(keeping: Set(profiles.compactMap(\.localImageFileName)))
        let missing = profiles.filter { $0.lastFetchedAt == nil }.map(\.id)
        await refresh(profileIDs: missing)
    }

    // MARK: - Intern

    private func scheduleRefresh(for profileID: UUID) {
        guard refreshesAutomatically else { return }
        Task { [weak self] in
            await self?.refreshMetadata(for: profileID)
        }
    }

    private func invalidateFetch(for profileID: UUID) {
        fetchTokens[profileID] = nil
        loadingProfileIDs.remove(profileID)
    }

    private func isFetchCurrent(profileID: UUID, token: UUID, username: String) -> Bool {
        guard fetchTokens[profileID] == token, let current = profile(with: profileID) else { return false }
        return current.username == username
    }

    private func updateCompleteness(of profile: TikTokProfile, fetchedName: Bool? = nil) {
        let hasName = profile.displayName != nil
        let hasImage = profile.localImageFileName != nil
        if hasName && hasImage {
            incompleteProfileIDs.remove(profile.id)
        } else if fetchedName != nil {
            // Nur nach einem tatsächlich erfolgten Abruf auf fehlende Daten hinweisen.
            incompleteProfileIDs.insert(profile.id)
        }
    }

    private static func normalizedManualName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
