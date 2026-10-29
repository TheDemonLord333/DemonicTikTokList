//
//  TikTokProfileService.swift
//  DemonicTikTokList
//

import Foundation

/// Netzwerkfehler mit verständlichen deutschen Beschreibungen.
nonisolated enum TikTokServiceError: LocalizedError, Equatable, Sendable {
    case offline
    case timedOut
    case network
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Keine Internetverbindung."
        case .timedOut:
            return "Die Anfrage hat zu lange gedauert."
        case .network:
            return "Die Verbindung zu TikTok ist fehlgeschlagen."
        case .invalidResponse:
            return "TikTok hat eine unerwartete Antwort gesendet."
        case .httpStatus(let code):
            return "TikTok hat die Anfrage abgelehnt (HTTP \(code))."
        case .responseTooLarge:
            return "Die Antwort von TikTok war zu groß."
        case .notAnImage:
            return "Das Profilbild konnte nicht gelesen werden."
        }
    }
}

/// Abstraktion des Profilabrufs, damit Logik und Tests ohne Netzwerk auskommen.
nonisolated protocol TikTokProfileServicing: Sendable {
    /// Folgt den Weiterleitungen eines Kurzlinks und liefert die endgültige Ziel-URL.
    func resolveShortLink(_ url: URL) async throws -> URL
    /// Lädt öffentliche Metadaten best effort. Fehler führen zu leeren Feldern, nie zu einem Abbruch.
    func fetchMetadata(for username: String) async -> ProfileMetadata
    /// Lädt ein Profilbild und liefert verkleinerte JPEG-Daten.
    func downloadAvatar(from url: URL) async throws -> Data
}

/// Ruft Profildaten über TikToks dokumentierten Creator-oEmbed-Endpunkt und ergänzend
/// über öffentlich ausgelieferte Metadaten der Profilseite ab.
///
/// Es werden keine Anmeldedaten, API-Schlüssel oder Umgehungen von Zugriffsbeschränkungen
/// verwendet. Blockiert TikTok eine Anfrage, bleiben die betroffenen Felder leer.
nonisolated final class TikTokProfileService: TikTokProfileServicing {
    private static let maxJSONBytes = 512 * 1024
    private static let maxHTMLBytes = 4 * 1024 * 1024
    private static let maxImageBytes = 8 * 1024 * 1024
    private static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init(session: URLSession = TikTokProfileService.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept-Language": "de-DE,de;q=0.9,en;q=0.8"]
        return URLSession(configuration: configuration)
    }

    // MARK: - Kurzlinks

    func resolveShortLink(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await session.bytes(for: request)
        } catch {
            throw Self.mapError(error)
        }
        let (bytes, response) = result
        // Nur das Weiterleitungsziel wird benötigt, der Seiteninhalt nicht.
        bytes.task.cancel()

        guard let finalURL = response.url else { throw TikTokServiceError.invalidResponse }
        if let http = response as? HTTPURLResponse,
           !(200..<400).contains(http.statusCode),
           finalURL == url {
            throw TikTokServiceError.httpStatus(http.statusCode)
        }
        return finalURL
    }

    // MARK: - Metadaten

    func fetchMetadata(for username: String) async -> ProfileMetadata {
        var metadata = ProfileMetadata()

        if let oEmbed = try? await fetchOEmbedMetadata(username: username) {
            metadata = metadata.merged(with: oEmbed)
        }

        if metadata.displayName == nil || metadata.avatarURL == nil, !Task.isCancelled {
            if let page = try? await fetchProfilePageMetadata(username: username) {
                metadata = metadata.merged(with: page)
            }
        }
        return metadata
    }

    private func fetchOEmbedMetadata(username: String) async throws -> ProfileMetadata {
        guard let url = TikTokURLParser.oEmbedURL(forUsername: username) else {
            throw TikTokServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await fetchData(request, maxBytes: Self.maxJSONBytes)
        return ProfileMetadataParser.parseOEmbed(data, expectedUsername: username) ?? ProfileMetadata()
    }

    private func fetchProfilePageMetadata(username: String) async throws -> ProfileMetadata {
        guard let url = TikTokURLParser.canonicalProfileURL(for: username) else {
            throw TikTokServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let data = try await fetchData(request, maxBytes: Self.maxHTMLBytes)
        // Das Durchsuchen einer großen HTML-Seite gehört nicht auf den Main Thread.
        return await Task.detached(priority: .utility) {
            ProfileMetadataParser.parseProfilePage(data: data, expectedUsername: username)
        }.value
    }

    // MARK: - Profilbilder

    func downloadAvatar(from url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else { throw TikTokServiceError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let data = try await fetchData(request, maxBytes: Self.maxImageBytes)
        guard let processed = await ImageProcessing.downsampledJPEGInBackground(from: data) else {
            throw TikTokServiceError.notAnImage
        }
        return processed
    }

    // MARK: - Hilfen

    private func fetchData(_ request: URLRequest, maxBytes: Int) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw Self.mapError(error)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw TikTokServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw TikTokServiceError.httpStatus(http.statusCode) }
        guard data.count <= maxBytes else { throw TikTokServiceError.responseTooLarge }
        return data
    }

    private static func mapError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return TikTokServiceError.offline
        case .timedOut:
            return TikTokServiceError.timedOut
        case .cancelled:
            return CancellationError()
        default:
            return TikTokServiceError.network
        }
    }
}
