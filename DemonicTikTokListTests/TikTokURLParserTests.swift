//
//  TikTokURLParserTests.swift
//  DemonicTikTokListTests
//

import Foundation
import Testing
@testable import DemonicTikTokList

struct TikTokURLParserTests {

    // MARK: - URL-Normalisierung

    @Test(arguments: [
        "https://www.tiktok.com/@username",
        "https://tiktok.com/@username",
        "http://www.tiktok.com/@username",
        "www.tiktok.com/@username",
        "tiktok.com/@username",
        "https://m.tiktok.com/@username",
        "  https://www.tiktok.com/@username  \n",
        "https://www.tiktok.com/@username/",
        "https://www.tiktok.com/@UserName",
        "HTTPS://WWW.TIKTOK.COM/@username",
        "https://www.tiktok.com/@username?is_from_webapp=1&sender_device=pc",
        "https://www.tiktok.com/@username?_t=8abc&_r=1#top",
        "https://www.tiktok.com/%40username",
        "https://www.tiktok.com.:443/@username"
    ])
    func acceptsProfileLinkVariants(input: String) throws {
        #expect(try TikTokURLParser.parse(input) == .profile(username: "username"))
    }

    @Test func acceptsUsernamesWithDotsAndUnderscores() throws {
        #expect(try TikTokURLParser.parse("https://www.tiktok.com/@demon_lord.333") == .profile(username: "demon_lord.333"))
    }

    @Test func buildsCanonicalHTTPSLink() throws {
        let parsed = try TikTokURLParser.parse("tiktok.com/@Some.User?lang=de")
        guard case .profile(let username) = parsed else {
            Issue.record("Profil erwartet")
            return
        }
        let link = ValidatedProfileLink(username: username)
        #expect(link.canonicalURLString == "https://www.tiktok.com/@some.user")
        #expect(TikTokURLParser.canonicalProfileURL(for: username)?.absoluteString == "https://www.tiktok.com/@some.user")
    }

    @Test func buildsEncodedOEmbedURL() {
        let url = TikTokURLParser.oEmbedURL(forUsername: "scout2015")
        #expect(url?.absoluteString == "https://www.tiktok.com/oembed?url=https%3A%2F%2Fwww.tiktok.com%2F%40scout2015")
    }

    // MARK: - Domainprüfung

    @Test(arguments: [
        "https://tiktok.com.example.org/@username",
        "https://www.tiktok.com.evil.net/@username",
        "https://nottiktok.com/@username",
        "https://faketiktok.com/@username",
        "https://example.org/@username",
        "https://example.org/www.tiktok.com/@username",
        "https://tiktok.co/@username",
        "https://tiktok.com@example.org/@username",
        "https://www.tiktok.com:pass@example.org/@username",
        "https://www.youtube.com/@username",
        "https://shop.tiktok.com/@username"
    ])
    func rejectsForeignDomains(input: String) {
        #expect(throws: TikTokLinkError.foreignDomain) {
            try TikTokURLParser.parse(input)
        }
    }

    @Test(arguments: [
        "ftp://www.tiktok.com/@username",
        "javascript:alert(1)",
        "https://www.tiktok.com/@user name",
        "https://www.tiktok.com:8080/@username"
    ])
    func rejectsInvalidLinks(input: String) {
        #expect(throws: TikTokLinkError.self) {
            try TikTokURLParser.parse(input)
        }
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsEmptyInput(input: String) {
        #expect(throws: TikTokLinkError.empty) {
            try TikTokURLParser.parse(input)
        }
    }

    @Test(arguments: [
        "https://www.tiktok.com/@username/video/7234567890123456789",
        "https://www.tiktok.com/@username/video/7234567890123456789?is_from_webapp=1",
        "https://www.tiktok.com/@username/photo/7234567890123456789",
        "https://www.tiktok.com/embed/v2/7234567890123456789",
        "https://m.tiktok.com/v/7234567890123456789.html"
    ])
    func rejectsVideoLinks(input: String) {
        #expect(throws: TikTokLinkError.videoLink) {
            try TikTokURLParser.parse(input)
        }
    }

    @Test(arguments: [
        "https://www.tiktok.com",
        "https://www.tiktok.com/",
        "https://www.tiktok.com/explore",
        "https://www.tiktok.com/@username/live",
        "https://www.tiktok.com/tag/demon"
    ])
    func rejectsNonProfilePaths(input: String) {
        #expect(throws: TikTokLinkError.notAProfile) {
            try TikTokURLParser.parse(input)
        }
    }

    @Test(arguments: [
        "https://www.tiktok.com/@",
        "https://www.tiktok.com/@user!name",
        "https://www.tiktok.com/@user-name",
        "https://www.tiktok.com/@abcdefghijklmnopqrstuvwxyz"
    ])
    func rejectsInvalidUsernames(input: String) {
        #expect(throws: TikTokLinkError.invalidUsername) {
            try TikTokURLParser.parse(input)
        }
    }

    // MARK: - Kurzlinks

    @Test func recognizesShortLinks() throws {
        #expect(try TikTokURLParser.parse("https://vm.tiktok.com/ZMabc123/") == .shortLink(URL(string: "https://vm.tiktok.com/ZMabc123/")!))
        #expect(try TikTokURLParser.parse("vt.tiktok.com/ZSxyz789?share=1") == .shortLink(URL(string: "https://vt.tiktok.com/ZSxyz789/")!))
        #expect(try TikTokURLParser.parse("https://www.tiktok.com/t/ZTRabc123/") == .shortLink(URL(string: "https://www.tiktok.com/t/ZTRabc123/")!))
    }

    @Test func rejectsMalformedShortLinks() {
        #expect(throws: TikTokLinkError.notAProfile) {
            try TikTokURLParser.parse("https://vm.tiktok.com/")
        }
        #expect(throws: TikTokLinkError.notAProfile) {
            try TikTokURLParser.parse("https://vm.tiktok.com/abc/def")
        }
    }
}

struct ProfileDuplicateDetectorTests {

    @Test func detectsSameProfileWithDifferentTrackingParameters() throws {
        let first = try TikTokURLParser.parse("https://www.tiktok.com/@demonlord?is_from_webapp=1&sender_device=pc")
        let second = try TikTokURLParser.parse("tiktok.com/@DemonLord?_t=8xyz&_r=1#section")
        guard case .profile(let firstName) = first, case .profile(let secondName) = second else {
            Issue.record("Profile erwartet")
            return
        }
        #expect(ProfileDuplicateDetector.isDuplicate(username: secondName, existingUsernames: [firstName]))
    }

    @Test func comparesCaseInsensitivelyAndIgnoresAtSign() {
        #expect(ProfileDuplicateDetector.isDuplicate(username: "@DemonLord", existingUsernames: ["demonlord"]))
        #expect(ProfileDuplicateDetector.isDuplicate(username: " demonlord ", existingUsernames: ["other", "DEMONLORD"]))
    }

    @Test func distinguishesDifferentUsernames() {
        #expect(!ProfileDuplicateDetector.isDuplicate(username: "demonlord", existingUsernames: ["demonlord2", "demon.lord", "demon_lord"]))
        #expect(!ProfileDuplicateDetector.isDuplicate(username: "demonlord", existingUsernames: []))
    }
}
