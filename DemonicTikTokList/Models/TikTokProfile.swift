//
//  TikTokProfile.swift
//  DemonicTikTokList
//

import Foundation
import SwiftData

/// Herkunft des lokal gespeicherten Profilbildes.
nonisolated enum ProfileImageSource: String, Sendable {
    /// Automatisch aus öffentlichen TikTok-Metadaten geladen.
    case automatic
    /// Vom Nutzer über den PhotosPicker ausgewählt.
    case manual
}

/// Ein gespeicherter Eintrag der persönlichen TikTok-Profilliste.
@Model
final class TikTokProfile {
    /// Stabile Kennung des Eintrags.
    @Attribute(.unique) var id: UUID
    /// Kanonischer HTTPS-Profillink, z. B. `https://www.tiktok.com/@username`.
    var profileURLString: String
    /// Normalisierter Username (kleingeschrieben, ohne `@`).
    var username: String
    /// Automatisch ermittelter Anzeigename.
    var autoDisplayName: String?
    /// Optional manuell gesetzter Anzeigename. Hat Vorrang vor dem automatischen Namen.
    var manualDisplayName: String?
    /// Zuletzt ermittelte Remote-URL des Profilbildes.
    var remoteImageURLString: String?
    /// Dateiname des lokal gespeicherten Bildes in Application Support.
    var localImageFileName: String?
    /// Rohwert von `ProfileImageSource`.
    var imageSourceRaw: String?
    /// Erstellungsdatum, bestimmt die Reihenfolge der Liste.
    var createdAt: Date
    /// Zeitpunkt des letzten erfolgreichen Metadatenabrufs.
    var lastFetchedAt: Date?

    init(
        id: UUID = UUID(),
        username: String,
        profileURLString: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.username = username
        self.profileURLString = profileURLString
        self.createdAt = createdAt
    }

    var imageSource: ProfileImageSource? {
        get { imageSourceRaw.flatMap(ProfileImageSource.init(rawValue:)) }
        set { imageSourceRaw = newValue?.rawValue }
    }

    /// Anzuzeigender Name: manuell gesetzter Name vor automatisch ermitteltem Namen.
    var displayName: String? {
        if let manual = manualDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !manual.isEmpty {
            return manual
        }
        if let auto = autoDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !auto.isEmpty {
            return auto
        }
        return nil
    }

    var profileURL: URL? {
        URL(string: profileURLString)
    }

    var hasManualImage: Bool {
        imageSource == .manual && localImageFileName != nil
    }
}
