//
//  ContentView.swift
//  DemonicTikTokList
//

import SwiftData
import SwiftUI

/// Hauptansicht mit der Liste der gespeicherten TikTok-Profile.
struct ContentView: View {
    @Environment(ProfileListController.self) private var controller
    @Query(sort: \TikTokProfile.createdAt, order: .forward) private var profiles: [TikTokProfile]

    @State private var isEditing = false
    @State private var isAddingProfile = false
    @State private var profileBeingEdited: TikTokProfile?
    @State private var profilePendingDeletion: TikTokProfile?
    @State private var errorAlert: ErrorAlert?

    private let opener: any ProfileURLOpening

    init(opener: any ProfileURLOpening = SystemProfileURLOpener()) {
        self.opener = opener
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DemonicBackground()

                if profiles.isEmpty {
                    EmptyStateView { isAddingProfile = true }
                        .transition(.opacity)
                } else {
                    profileList
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: profiles.isEmpty)
            .navigationTitle("Demonic TikTok List")
            .toolbarBackground(Theme.background.opacity(0.9), for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingProfile) {
                ProfileFormSheet(mode: .add)
                    .environment(controller)
            }
            .sheet(item: $profileBeingEdited) { profile in
                ProfileFormSheet(mode: .edit(profile))
                    .environment(controller)
            }
            .alert(
                "Möchtest du dieses Profil aus deiner Liste löschen?",
                isPresented: isConfirmingDeletion,
                presenting: profilePendingDeletion
            ) { profile in
                Button("Löschen", role: .destructive) { delete(profile) }
                Button("Abbrechen", role: .cancel) {}
            } message: { profile in
                Text("@\(profile.username) wird nur aus dieser Liste entfernt.")
            }
            .alert(
                errorAlert?.title ?? "",
                isPresented: isShowingError,
                presenting: errorAlert
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
            .onChange(of: profiles.isEmpty) { _, isEmpty in
                if isEmpty {
                    isEditing = false
                }
            }
            .task {
                await controller.performLaunchMaintenance()
            }
        }
    }

    // MARK: - Liste

    private var profileList: some View {
        List {
            ForEach(profiles) { profile in
                ProfileRowView(
                    profile: profile,
                    isEditing: isEditing,
                    isLoading: controller.loadingProfileIDs.contains(profile.id),
                    isIncomplete: controller.incompleteProfileIDs.contains(profile.id),
                    onOpen: { open(profile) },
                    onEdit: { profileBeingEdited = profile },
                    onDelete: { profilePendingDeletion = profile }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        profilePendingDeletion = profile
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .tint(Theme.danger)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .refreshable {
            await controller.refreshAll()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(isEditing ? "Fertig" : "Bearbeiten") {
                isEditing.toggle()
            }
            .fontWeight(isEditing ? .semibold : .regular)
            .disabled(profiles.isEmpty && !isEditing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isAddingProfile = true
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Profil hinzufügen")
        }
    }

    // MARK: - Aktionen

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { profilePendingDeletion != nil },
            set: { if !$0 { profilePendingDeletion = nil } }
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )
    }

    /// Öffnet das Profil außerhalb der App: per Universal Link in TikTok oder im Browser.
    private func open(_ profile: TikTokProfile) {
        // Im Bearbeitungsmodus darf TikTok nie geöffnet werden.
        guard !isEditing else { return }
        guard let url = profile.profileURL else {
            errorAlert = ErrorAlert(
                title: "Profil konnte nicht geöffnet werden",
                message: "Der gespeicherte Profillink ist ungültig. Bitte bearbeite das Profil."
            )
            return
        }
        Task {
            let opened = await opener.open(url)
            if !opened {
                errorAlert = ErrorAlert(
                    title: "Profil konnte nicht geöffnet werden",
                    message: "Weder TikTok noch der Browser konnten @\(profile.username) öffnen. Bitte versuche es erneut."
                )
            }
        }
    }

    private func delete(_ profile: TikTokProfile) {
        let id = profile.id
        profilePendingDeletion = nil
        do {
            try withAnimation {
                try controller.deleteProfile(with: id)
            }
        } catch {
            errorAlert = ErrorAlert(
                title: "Löschen fehlgeschlagen",
                message: (error as? LocalizedError)?.errorDescription ?? "Das Profil konnte nicht gelöscht werden."
            )
        }
    }
}

private struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#if DEBUG
#Preview("Mit Profilen") {
    PreviewSupport.makeRoot(withSamples: true)
}

#Preview("Leere Liste") {
    PreviewSupport.makeRoot(withSamples: false)
}
#endif
