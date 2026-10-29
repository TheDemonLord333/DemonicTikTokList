//
//  ProfileMetadataParser.swift
//  DemonicTikTokList
//

import Foundation

/// Öffentlich ermittelte Profildaten. Alle Werte sind optional, da der Abruf best effort ist.
nonisolated struct ProfileMetadata: Equatable, Sendable {
    var displayName: String?
    var avatarURL: URL?

    init(displayName: String? = nil, avatarURL: URL? = nil) {
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    var isEmpty: Bool {
        displayName == nil && avatarURL == nil
    }

    /// Bevorzugt die eigenen Werte und ergänzt fehlende Werte aus `other`.
    func merged(with other: ProfileMetadata) -> ProfileMetadata {
        ProfileMetadata(
            displayName: displayName ?? other.displayName,
            avatarURL: avatarURL ?? other.avatarURL
        )
    }
}

/// Wertet oEmbed-Antworten und öffentlich ausgelieferte Profilseiten aus.
///
/// Es werden nur Werte übernommen, die eindeutig zum erwarteten Username gehören.
/// Ändert TikTok die Seitenstruktur, liefert der Parser einfach leere Ergebnisse.
nonisolated enum ProfileMetadataParser {
    private static let maxDisplayNameLength = 80

    /// CDN-Domains, von denen TikTok Profilbilder ausliefert.
    private static let avatarHostSuffixes = [
        "tiktokcdn.com",
        "tiktokcdn-us.com",
        "tiktokcdn-eu.com",
        "ibyteimg.com",
        "byteimg.com"
    ]

    // MARK: - oEmbed

    /// Wertet die Antwort des Creator-oEmbed-Endpunkts aus. Gibt `nil` zurück, wenn die Antwort
    /// erkennbar zu einem anderen Profil gehört oder kein gültiges JSON ist.
    static func parseOEmbed(_ data: Data, expectedUsername: String) -> ProfileMetadata? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let expected = expectedUsername.lowercased()

        if let authorURL = object["author_url"] as? String, !authorURL.isEmpty {
            guard let parsed = try? TikTokURLParser.parse(authorURL),
                  case .profile(let username) = parsed,
                  username == expected else {
                return nil
            }
        }
        if let html = object["html"] as? String,
           let uniqueID = attributeValue(named: "data-unique-id", in: html),
           uniqueID.lowercased() != expected {
            return nil
        }

        // oEmbed liefert für Creator kein verlässliches Profilbild, daher nur den Namen übernehmen.
        return ProfileMetadata(displayName: cleanedDisplayName(object["author_name"] as? String))
    }

    // MARK: - Profilseite

    static func parseProfilePage(data: Data, expectedUsername: String) -> ProfileMetadata {
        parseProfilePage(html: String(decoding: data, as: UTF8.self), expectedUsername: expectedUsername)
    }

    static func parseProfilePage(html: String, expectedUsername: String) -> ProfileMetadata {
        let expected = expectedUsername.lowercased()
        var result = ProfileMetadata()

        for scriptID in ["__UNIVERSAL_DATA_FOR_REHYDRATION__", "SIGI_STATE"] {
            guard let json = jsonScript(withID: scriptID, in: html),
                  let user = userObject(in: json, expectedUsername: expected) else {
                continue
            }
            result = result.merged(with: metadata(fromUser: user, expectedUsername: expected))
        }

        if result.displayName == nil || result.avatarURL == nil {
            result = result.merged(with: openGraphMetadata(in: html, expectedUsername: expected))
        }
        return result
    }

    static func jsonScript(withID id: String, in html: String) -> [String: Any]? {
        guard let idRange = html.range(of: "id=\"\(id)\""),
              let tagEnd = html.range(of: ">", range: idRange.upperBound..<html.endIndex),
              let closingTag = html.range(of: "</script>", range: tagEnd.upperBound..<html.endIndex) else {
            return nil
        }
        let json = html[tagEnd.upperBound..<closingTag.lowerBound]
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    static func userObject(in json: [String: Any], expectedUsername: String) -> [String: Any]? {
        if let scope = json["__DEFAULT_SCOPE__"] as? [String: Any],
           let detail = scope["webapp.user-detail"] as? [String: Any],
           let userInfo = detail["userInfo"] as? [String: Any],
           let user = userInfo["user"] as? [String: Any] {
            return user
        }
        if let module = json["UserModule"] as? [String: Any],
           let users = module["users"] as? [String: Any] {
            for (key, value) in users where key.lowercased() == expectedUsername {
                if let user = value as? [String: Any] {
                    return user
                }
            }
        }
        return nil
    }

    static func metadata(fromUser user: [String: Any], expectedUsername: String) -> ProfileMetadata {
        guard let uniqueID = user["uniqueId"] as? String,
              uniqueID.lowercased() == expectedUsername else {
            return ProfileMetadata()
        }
        var metadata = ProfileMetadata(displayName: cleanedDisplayName(user["nickname"] as? String))
        for key in ["avatarLarger", "avatarMedium", "avatarThumb"] {
            if let string = user[key] as? String,
               let url = URL(string: string),
               isTrustedAvatarURL(url, requireAvatarPath: false) {
                metadata.avatarURL = url
                break
            }
        }
        return metadata
    }

    /// Fallback über Open-Graph-Metadaten. Werte werden nur übernommen, wenn die Seite
    /// eindeutig zum erwarteten Profil gehört.
    static func openGraphMetadata(in html: String, expectedUsername: String) -> ProfileMetadata {
        let tags = metaTags(in: html)
        let title = tags["og:title"] ?? tags["twitter:title"]

        var belongsToProfile = false
        if let ogURL = tags["og:url"],
           let parsed = try? TikTokURLParser.parse(ogURL),
           case .profile(let username) = parsed {
            guard username == expectedUsername else { return ProfileMetadata() }
            belongsToProfile = true
        }
        let nameFromTitle = title.flatMap { Self.displayName(fromTitle: $0, expectedUsername: expectedUsername) }
        if nameFromTitle != nil {
            belongsToProfile = true
        }
        guard belongsToProfile else { return ProfileMetadata() }

        var metadata = ProfileMetadata(displayName: nameFromTitle)
        if let image = tags["og:image"] ?? tags["twitter:image"],
           let url = URL(string: image),
           isTrustedAvatarURL(url, requireAvatarPath: true) {
            metadata.avatarURL = url
        }
        return metadata
    }

    /// Profiltitel haben die Form `Anzeigename (@username) | TikTok`.
    static func displayName(fromTitle title: String, expectedUsername: String) -> String? {
        let pattern = "^(.*?)\\s*\\(@" + NSRegularExpression.escapedPattern(for: expectedUsername) + "\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsTitle = title as NSString
        guard let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: nsTitle.length)),
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        return cleanedDisplayName(nsTitle.substring(with: match.range(at: 1)))
    }

    /// Profilbilder müssen per HTTPS von TikToks CDN stammen. Für Open-Graph-Bilder wird
    /// zusätzlich der Avatar-Pfad verlangt, damit kein Logo oder Video-Vorschaubild übernommen wird.
    static func isTrustedAvatarURL(_ url: URL, requireAvatarPath: Bool) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        let trustedHost = avatarHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
        guard trustedHost else { return false }
        if requireAvatarPath {
            return url.path.lowercased().contains("-avt-")
        }
        return true
    }

    // MARK: - HTML-Hilfen

    static func metaTags(in html: String) -> [String: String] {
        guard let tagRegex = try? NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive]),
              let attributeRegex = try? NSRegularExpression(
                pattern: "([a-zA-Z_:-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')",
                options: []
              ) else {
            return [:]
        }
        let nsHTML = html as NSString
        var result: [String: String] = [:]
        for match in tagRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            let tag = nsHTML.substring(with: match.range)
            let nsTag = tag as NSString
            var attributes: [String: String] = [:]
            for attribute in attributeRegex.matches(in: tag, range: NSRange(location: 0, length: nsTag.length)) {
                let name = nsTag.substring(with: attribute.range(at: 1)).lowercased()
                let valueRange = attribute.range(at: 2).location != NSNotFound
                    ? attribute.range(at: 2)
                    : attribute.range(at: 3)
                guard valueRange.location != NSNotFound else { continue }
                attributes[name] = decodeHTMLEntities(nsTag.substring(with: valueRange))
            }
            guard let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
                  let content = attributes["content"],
                  result[key] == nil else {
                continue
            }
            result[key] = content
        }
        return result
    }

    static func attributeValue(named name: String, in html: String) -> String? {
        let pattern = NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsHTML.length)) else {
            return nil
        }
        return decodeHTMLEntities(nsHTML.substring(with: match.range(at: 1)))
    }

    static func cleanedDisplayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maxDisplayNameLength else { return nil }
        return value
    }

    static func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            let character = string[index]
            if character == "&",
               let semicolon = string[index...].firstIndex(of: ";"),
               string.distance(from: index, to: semicolon) <= 10 {
                let entity = String(string[string.index(after: index)..<semicolon])
                if let decoded = decodeEntity(entity) {
                    result.append(decoded)
                    index = string.index(after: semicolon)
                    continue
                }
            }
            result.append(character)
            index = string.index(after: index)
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> Character? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default: break
        }
        guard entity.hasPrefix("#") else { return nil }
        let number = entity.dropFirst()
        let value: UInt32?
        if number.hasPrefix("x") || number.hasPrefix("X") {
            value = UInt32(number.dropFirst(), radix: 16)
        } else {
            value = UInt32(number, radix: 10)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return Character(scalar)
    }
}
