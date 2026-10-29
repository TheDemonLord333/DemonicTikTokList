//
//  ProfileMetadataParserTests.swift
//  DemonicTikTokListTests
//

import Foundation
import Testing
@testable import DemonicTikTokList

struct ProfileMetadataParserTests {

    // MARK: - oEmbed

    @Test func readsAuthorNameFromMatchingOEmbedResponse() throws {
        let json = """
        {
          "version": "1.0",
          "type": "rich",
          "title": "TikTok",
          "author_url": "https://www.tiktok.com/@scout2015",
          "author_name": "Scout &amp; Friends",
          "html": "<blockquote class=\\"tiktok-embed\\" cite=\\"https://www.tiktok.com/@scout2015\\" data-unique-id=\\"scout2015\\" data-embed-type=\\"creator\\"></blockquote>",
          "thumbnail_url": "https://p16.tiktokcdn.com/obj/some-video-cover.jpeg",
          "provider_name": "TikTok"
        }
        """
        let metadata = try #require(ProfileMetadataParser.parseOEmbed(Data(json.utf8), expectedUsername: "scout2015"))
        #expect(metadata.displayName == "Scout & Friends")
        // oEmbed-Vorschaubilder werden bewusst nicht als Profilbild übernommen.
        #expect(metadata.avatarURL == nil)
    }

    @Test func rejectsOEmbedResponseForOtherProfile() {
        let json = """
        {"author_url": "https://www.tiktok.com/@someoneelse", "author_name": "Falscher Name"}
        """
        #expect(ProfileMetadataParser.parseOEmbed(Data(json.utf8), expectedUsername: "scout2015") == nil)
    }

    @Test func rejectsOEmbedResponseWithMismatchingUniqueID() {
        let json = """
        {"author_name": "Falscher Name", "html": "<blockquote data-unique-id=\\"other\\"></blockquote>"}
        """
        #expect(ProfileMetadataParser.parseOEmbed(Data(json.utf8), expectedUsername: "scout2015") == nil)
    }

    @Test func returnsNilForInvalidJSON() {
        #expect(ProfileMetadataParser.parseOEmbed(Data("<html>Blocked</html>".utf8), expectedUsername: "scout2015") == nil)
    }

    // MARK: - Strukturierte Profildaten

    @Test func readsStructuredProfileData() {
        let html = """
        <html><head><title>TikTok</title></head><body>
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
        {"__DEFAULT_SCOPE__":{"webapp.user-detail":{"userInfo":{"user":{
          "uniqueId":"DemonLord",
          "nickname":"The Demon Lord",
          "avatarLarger":"https:\\/\\/p16-sign-va.tiktokcdn.com\\/tos-maliva-avt-0068\\/abc~c5_1080x1080.jpeg?x-expires=1",
          "avatarThumb":"https:\\/\\/p16-sign-va.tiktokcdn.com\\/tos-maliva-avt-0068\\/abc~c5_100x100.jpeg"
        }}}}}
        </script></body></html>
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.displayName == "The Demon Lord")
        #expect(metadata.avatarURL?.host == "p16-sign-va.tiktokcdn.com")
        #expect(metadata.avatarURL?.path.contains("1080x1080") == true)
    }

    @Test func ignoresStructuredDataOfOtherUser() {
        let html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
        {"__DEFAULT_SCOPE__":{"webapp.user-detail":{"userInfo":{"user":{
          "uniqueId":"someoneelse","nickname":"Fremd",
          "avatarLarger":"https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/x.jpeg"
        }}}}}
        </script>
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.isEmpty)
    }

    @Test func ignoresAvatarFromUntrustedHost() {
        let html = """
        <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
        {"__DEFAULT_SCOPE__":{"webapp.user-detail":{"userInfo":{"user":{
          "uniqueId":"demonlord","nickname":"Demon",
          "avatarLarger":"https://tiktokcdn.com.example.org/tos-maliva-avt-0068/x.jpeg"
        }}}}}
        </script>
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.displayName == "Demon")
        #expect(metadata.avatarURL == nil)
    }

    // MARK: - Open Graph

    @Test func readsOpenGraphFallback() {
        let html = """
        <meta property="og:title" content="Grüne &amp; Flamme (@demonlord) | TikTok">
        <meta property="og:url" content="https://www.tiktok.com/@demonlord">
        <meta property="og:image" content="https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/abc.jpeg?x=1&amp;y=2">
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.displayName == "Grüne & Flamme")
        #expect(metadata.avatarURL?.absoluteString == "https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/abc.jpeg?x=1&y=2")
    }

    @Test func rejectsGenericOpenGraphImage() {
        let html = """
        <meta property="og:title" content="Demon (@demonlord) | TikTok">
        <meta property="og:image" content="https://sf16-website-login.neutral.ttwstatic.com/obj/tiktok_web_login_static/tiktok/webapp/main/webapp-desktop/logo.png">
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.displayName == "Demon")
        #expect(metadata.avatarURL == nil)
    }

    @Test func rejectsVideoCoverAsOpenGraphImage() {
        let html = """
        <meta property="og:url" content="https://www.tiktok.com/@demonlord">
        <meta property="og:image" content="https://p16-sign-va.tiktokcdn.com/obj/tos-maliva-p-0068/videocover.jpeg">
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.avatarURL == nil)
    }

    @Test func ignoresOpenGraphDataOfOtherProfile() {
        let html = """
        <meta property="og:title" content="Fremd (@someoneelse) | TikTok">
        <meta property="og:url" content="https://www.tiktok.com/@someoneelse">
        <meta property="og:image" content="https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/abc.jpeg">
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.isEmpty)
    }

    @Test func ignoresGenericTikTokPage() {
        let html = """
        <meta property="og:title" content="TikTok - Make Your Day">
        <meta property="og:image" content="https://p16-sign-va.tiktokcdn.com/tos-maliva-avt-0068/abc.jpeg">
        """
        let metadata = ProfileMetadataParser.parseProfilePage(html: html, expectedUsername: "demonlord")
        #expect(metadata.isEmpty)
    }

    @Test func decodesHTMLEntities() {
        #expect(ProfileMetadataParser.decodeHTMLEntities("A &amp; B &lt;3 &#39;x&#x27; &quot;y&quot;") == "A & B <3 'x' \"y\"")
        #expect(ProfileMetadataParser.decodeHTMLEntities("Kein & Entity") == "Kein & Entity")
    }
}
