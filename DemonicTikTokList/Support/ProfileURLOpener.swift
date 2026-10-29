//
//  ProfileURLOpener.swift
//  DemonicTikTokList
//

import UIKit

/// Öffnet Profillinks außerhalb der App.
protocol ProfileURLOpening {
    func open(_ url: URL) async -> Bool
}

/// Übergibt den kanonischen HTTPS-Profillink an iOS.
///
/// Zuerst wird ausschließlich als Universal Link geöffnet: Ist TikTok installiert und für
/// `www.tiktok.com` registriert, öffnet iOS direkt die TikTok-App. Andernfalls wird derselbe
/// HTTPS-Link regulär geöffnet, also im Standardbrowser. Es werden keine eigenen URL-Schemes
/// und keine eingebettete WebView verwendet.
struct SystemProfileURLOpener: ProfileURLOpening {
    func open(_ url: URL) async -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        let application = UIApplication.shared
        if await application.open(url, options: [.universalLinksOnly: true]) {
            return true
        }
        return await application.open(url, options: [:])
    }
}
