//
//  Theme.swift
//  DemonicTikTokList
//

import SwiftUI

/// Farben und wiederverwendbare Stile im Look des AppIcons.
enum Theme {
    /// Fast schwarzer Hintergrund.
    static let background = Color(red: 0.027, green: 0.027, blue: 0.045)
    /// Dunkle Karten.
    static let card = Color(red: 0.075, green: 0.078, blue: 0.115)
    static let cardElevated = Color(red: 0.105, green: 0.108, blue: 0.16)
    /// Discord-Blau-Violett (#5865F2) als Hauptfarbe.
    static let blurple = Color(red: 0.345, green: 0.396, blue: 0.949)
    static let violet = Color(red: 0.50, green: 0.34, blue: 0.96)
    /// Spotify-Grün (#1DB954) für wichtige Akzente.
    static let spotifyGreen = Color(red: 0.114, green: 0.725, blue: 0.329)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.70)
    static let danger = Color(red: 0.95, green: 0.30, blue: 0.32)

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [blurple, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var glowStroke: LinearGradient {
        LinearGradient(
            colors: [blurple.opacity(0.65), violet.opacity(0.35), spotifyGreen.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Hintergrund mit dezentem blau-violettem und grünem Leuchten.
struct DemonicBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.blurple.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [Theme.spotifyGreen.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// Dunkle, abgerundete Karte mit leuchtendem Rand.
struct DemonicCardModifier: ViewModifier {
    var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isHighlighted ? Theme.cardElevated : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.glowStroke, lineWidth: 1)
            )
            .shadow(color: Theme.blurple.opacity(isHighlighted ? 0.35 : 0.18), radius: isHighlighted ? 16 : 10, y: 4)
    }
}

extension View {
    func demonicCard(highlighted: Bool = false) -> some View {
        modifier(DemonicCardModifier(isHighlighted: highlighted))
    }
}

/// Dezente Druck-Animation für antippbare Karten.
struct ProfileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
