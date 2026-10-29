//
//  ProfileRowView.swift
//  DemonicTikTokList
//

import SwiftUI

/// Ein Listeneintrag. Außerhalb des Bearbeitungsmodus ist die ganze Karte ein Button,
/// der das Profil auf TikTok öffnet. Im Bearbeitungsmodus gibt es nur Bearbeiten und Löschen.
struct ProfileRowView: View {
    let profile: TikTokProfile
    let isEditing: Bool
    let isLoading: Bool
    let isIncomplete: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var actionSize: CGFloat = 40

    var body: some View {
        if isEditing {
            content
                .demonicCard()
                .accessibilityElement(children: .contain)
        } else {
            Button(action: onOpen) {
                content
                    .demonicCard()
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(ProfileCardButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityHint("Öffnet das Profil auf TikTok.")
            .accessibilityAddTraits(.isLink)
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            ProfileAvatarView(fileName: profile.localImageFileName, isLoading: isLoading, size: avatarSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.displayName ?? "Anzeigename nicht verfügbar")
                    .font(.headline)
                    .foregroundStyle(profile.displayName == nil ? Theme.textSecondary : Theme.textPrimary)
                    .italic(profile.displayName == nil)
                    .lineLimit(2)

                Text("@\(profile.username)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.spotifyGreen)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if isLoading {
                    Text("Profildaten werden geladen …")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if isIncomplete {
                    Text("Einige Profildaten konnten nicht geladen werden.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditing {
                editActions
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.blurple)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editActions: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .frame(width: actionSize, height: actionSize)
                    .background(Circle().fill(Theme.blurple.opacity(0.22)))
                    .foregroundStyle(Theme.blurple)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Profil @\(profile.username) bearbeiten")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .frame(width: actionSize, height: actionSize)
                    .background(Circle().fill(Theme.danger.opacity(0.18)))
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Profil @\(profile.username) löschen")
        }
    }

    private var accessibilityTitle: String {
        var parts = [profile.displayName ?? "Anzeigename nicht verfügbar", "@\(profile.username)"]
        if isLoading {
            parts.append("Profildaten werden geladen")
        } else if isIncomplete {
            parts.append("Einige Profildaten konnten nicht geladen werden")
        }
        return parts.joined(separator: ", ")
    }
}
