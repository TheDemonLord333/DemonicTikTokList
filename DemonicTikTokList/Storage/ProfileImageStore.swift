//
//  ProfileImageStore.swift
//  DemonicTikTokList
//

import Foundation
import UIKit

/// Speichert Profilbilder dauerhaft in Application Support, damit sie auch offline sichtbar bleiben.
nonisolated final class ProfileImageStore: @unchecked Sendable {
    let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("ProfileImages", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        cache.countLimit = 200
    }

    /// Schreibt die Bilddaten unter einem neuen, eindeutigen Dateinamen.
    func save(_ data: Data) throws -> String {
        let fileName = UUID().uuidString + ".jpg"
        try data.write(to: fileURL(for: fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return fileName
    }

    func delete(named fileName: String?) {
        guard let fileName, Self.isValidFileName(fileName) else { return }
        cache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }

    func fileExists(named fileName: String) -> Bool {
        guard Self.isValidFileName(fileName) else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    func cachedImage(named fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    /// Lädt ein Bild von der Festplatte, ohne den Main Thread mit Dateizugriffen zu blockieren.
    func loadImage(named fileName: String?) async -> UIImage? {
        guard let fileName, Self.isValidFileName(fileName) else { return nil }
        if let cached = cachedImage(named: fileName) {
            return cached
        }
        let url = fileURL(for: fileName)
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        guard let data, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }

    /// Entfernt Dateien, auf die kein Profil mehr verweist (z. B. nach einem Absturz beim Ersetzen).
    func removeOrphanedFiles(keeping referencedFileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !referencedFileNames.contains(file) {
            delete(named: file)
        }
    }

    private func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Verhindert Pfadangaben wie `../` in gespeicherten Dateinamen.
    private static func isValidFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty && !fileName.contains("/") && !fileName.hasPrefix(".")
    }
}
