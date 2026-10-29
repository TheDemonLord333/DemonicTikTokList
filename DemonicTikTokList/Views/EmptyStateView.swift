//
//  EmptyStateView.swift
//  DemonicTikTokList
//

import SwiftUI

/// Ansicht für eine leere Liste.
struct EmptyStateView: View {
    let onAdd: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var logoSize: CGFloat = 150
    @State private var isGlowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: min(logoSize, 220), height: min(logoSize, 220))
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .shadow(color: Theme.blurple.opacity(isGlowing ? 0.55 : 0.3), radius: isGlowing ? 26 : 16)
                        .shadow(color: Theme.spotifyGreen.opacity(0.2), radius: 30)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Deine Liste ist noch leer")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Füge dein erstes TikTok-Profil über + hinzu")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .multilineTextAlignment(.center)

                    Button(action: onAdd) {
                        Label("Profil hinzufügen", systemImage: "plus")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Theme.primaryGradient))
                            .foregroundStyle(.white)
                            .shadow(color: Theme.blurple.opacity(0.5), radius: 12, y: 4)
                    }
                    .buttonStyle(ProfileCardButtonStyle())
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}
