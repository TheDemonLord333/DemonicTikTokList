//
//  ProfileAvatarView.swift
//  DemonicTikTokList
//

import SwiftUI
import UIKit

/// Rundes Profilbild aus dem lokalen Bildspeicher mit Platzhalter und dezentem Ladering.
struct ProfileAvatarView: View {
    @Environment(ProfileListController.self) private var controller

    let fileName: String?
    var overrideImage: UIImage?
    var isLoading = false
    var size: CGFloat = 52

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.cardElevated, Theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if let image = overrideImage ?? loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.25)
                    .foregroundStyle(Theme.spotifyGreen.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.glowStroke, lineWidth: 2))
        .overlay {
            if isLoading {
                LoadingRing()
                    .padding(-4)
            }
        }
        .shadow(color: Theme.spotifyGreen.opacity(0.25), radius: 6)
        .animation(.easeInOut(duration: 0.25), value: loadedImage != nil)
        .task(id: fileName) {
            if let fileName, let cached = controller.imageStore.cachedImage(named: fileName) {
                loadedImage = cached
            } else {
                loadedImage = await controller.imageStore.loadImage(named: fileName)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Kreisender Bogen als zurückhaltende Ladeanzeige. Respektiert „Bewegung reduzieren“.
private struct LoadingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRotating = false

    var body: some View {
        if reduceMotion {
            Circle()
                .stroke(Theme.blurple.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
        } else {
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Theme.blurple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isRotating)
                .onAppear { isRotating = true }
        }
    }
}
