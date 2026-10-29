//
//  TikTokURLParser.swift
//  DemonicTikTokList
//

import Foundation

/// Verständliche Fehler bei der Prüfung eines eingegebenen TikTok-Links.
nonisolated enum TikTokLinkError: LocalizedError, Equatable, Sendable {
    case empty
    case invalidURL
    case foreignDomain
    case videoLink
    case notAProfile
    case invalidUsername
    case shortLinkUnresolvable
    case shortLinkIsVideo
    case shortLinkNotProfile
    case duplicate

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Bitte gib einen TikTok-Profillink ein."
        case .invalidURL:
            return "Das ist kein gültiger Link. Beispiel: https://www.tiktok.com/@username"
        case .foreignDomain:
            return "Der Link gehört nicht zu TikTok. Bitte verwende einen Link von tiktok.com."
        case .videoLink:
            return "Das ist ein Video-Link. Bitte gib den Link zu einem TikTok-Profil ein."
        case .notAProfile:
            return "Der Link verweist nicht auf ein TikTok-Profil."
        case .invalidUsername:
            return "Der Username im Link ist ungültig."
        case .shortLinkUnresolvable:
            return "Der Kurzlink konnte nicht aufgelöst werden. Prüfe deine Internetverbindung oder verwende den vollständigen Profillink."
        case .shortLinkIsVideo:
            return "Der Kurzlink führt zu einem Video, nicht zu einem Profil."
        case .shortLinkNotProfile:
            return "Der Kurzlink führt nicht zu einem TikTok-Profil."
        case .duplicate:
            return "Dieses Profil ist bereits in deiner Liste."
        }
    }
}

/// Ergebnis der rein lokalen Linkprüfung.
nonisolated enum ParsedTikTokLink: Equatable, Sendable {
    /// Gültiger Profillink mit normalisiertem Username.
    case profile(username: String)
    /// TikTok-Kurzlink, der erst über das Netzwerk aufgelöst werden muss.
    case shortLink(URL)
}

/// Ein geprüfter, kanonischer Profillink.
nonisolated struct ValidatedProfileLink: Equatable, Sendable {
    let username: String

    var canonicalURLString: String {
        TikTokURLParser.canonicalProfileURLString(for: username)
    }
}

/// Prüft und normalisiert TikTok-Links ohne Netzwerkzugriff.
nonisolated enum TikTokURLParser {
    /// Hosts, unter denen Profilseiten erreichbar sind. Es wird exakt verglichen,
    /// damit Domains wie `tiktok.com.example.org` nicht akzeptiert werden.
    static let profileHosts: Set<String> = ["tiktok.com", "www.tiktok.com", "m.tiktok.com"]
    /// Hosts der offiziellen TikTok-Kurzlinks.
    static let shortLinkHosts: Set<String> = ["vm.tiktok.com", "vt.tiktok.com"]

    static let maxUsernameLength = 24

    static func parse(_ rawInput: String) throws -> ParsedTikTokLink {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw TikTokLinkError.empty }
        guard !input.contains(where: { $0.isWhitespace }) else { throw TikTokLinkError.invalidURL }

        var candidate = input
        if let schemeSeparator = candidate.range(of: "://") {
            let scheme = candidate[..<schemeSeparator.lowerBound].lowercased()
            guard scheme == "https" || scheme == "http" else { throw TikTokLinkError.invalidURL }
        } else {
            candidate = "https://" + candidate
        }

        guard let components = URLComponents(string: candidate),
              let rawHost = components.host,
              !rawHost.isEmpty else {
            throw TikTokLinkError.invalidURL
        }
        // Benutzerinformationen wie in `https://tiktok.com@example.org` sind ein typischer Täuschungsversuch.
        guard components.user == nil, components.password == nil else {
            throw TikTokLinkError.foreignDomain
        }
        if let port = components.port, port != 443, port != 80 {
            throw TikTokLinkError.invalidURL
        }

        var host = rawHost.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }

        let segments = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if shortLinkHosts.contains(host) {
            guard segments.count == 1, isValidShortCode(segments[0]),
                  let url = URL(string: "https://\(host)/\(segments[0])/") else {
                throw TikTokLinkError.notAProfile
            }
            return .shortLink(url)
        }

        guard profileHosts.contains(host) else { throw TikTokLinkError.foreignDomain }
        guard let first = segments.first else { throw TikTokLinkError.notAProfile }

        if first.lowercased() == "t" {
            guard segments.count == 2, isValidShortCode(segments[1]),
                  let url = URL(string: "https://www.tiktok.com/t/\(segments[1])/") else {
                throw TikTokLinkError.notAProfile
            }
            return .shortLink(url)
        }

        if first.hasPrefix("@") {
            let username = String(first.dropFirst())
            if segments.count > 1 {
                let second = segments[1].lowercased()
                if second == "video" || second == "photo" {
                    throw TikTokLinkError.videoLink
                }
                throw TikTokLinkError.notAProfile
            }
            guard isValidUsername(username) else { throw TikTokLinkError.invalidUsername }
            return .profile(username: username.lowercased())
        }

        let lowercasedSegments = segments.map { $0.lowercased() }
        if lowercasedSegments.contains("video") || lowercasedSegments.contains("photo")
            || ["v", "embed"].contains(lowercasedSegments[0]) {
            throw TikTokLinkError.videoLink
        }
        throw TikTokLinkError.notAProfile
    }

    /// TikTok-Usernames bestehen aus Buchstaben, Ziffern, Unterstrichen und Punkten.
    static func isValidUsername(_ username: String) -> Bool {
        guard (1...maxUsernameLength).contains(username.count) else { return false }
        return username.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == ".")
        }
    }

    static func isValidShortCode(_ code: String) -> Bool {
        guard (1...32).contains(code.count) else { return false }
        return code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    static func canonicalProfileURLString(for username: String) -> String {
        "https://www.tiktok.com/@\(username.lowercased())"
    }

    static func canonicalProfileURL(for username: String) -> URL? {
        guard isValidUsername(username) else { return nil }
        return URL(string: canonicalProfileURLString(for: username))
    }

    /// Dokumentierter oEmbed-Endpunkt für Creator-Profile.
    static func oEmbedURL(forUsername username: String) -> URL? {
        guard isValidUsername(username) else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = canonicalProfileURLString(for: username)
            .addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.tiktok.com/oembed?url=\(encoded)")
    }
}

/// Erkennt bereits gespeicherte Profile anhand des normalisierten Usernames.
nonisolated enum ProfileDuplicateDetector {
    static func normalizedUsername(_ username: String) -> String {
        var value = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        return value
    }

    static func isDuplicate<S: Sequence>(username: String, existingUsernames: S) -> Bool where S.Element == String {
        let candidate = normalizedUsername(username)
        return existingUsernames.contains { normalizedUsername($0) == candidate }
    }
}
