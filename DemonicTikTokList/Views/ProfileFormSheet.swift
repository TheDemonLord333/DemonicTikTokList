//
//  ProfileFormSheet.swift
//  DemonicTikTokList
//

import PhotosUI
import SwiftUI
import UIKit

/// Sheet zum Hinzufügen und Bearbeiten eines Profils. Änderungen werden erst beim
/// Speichern übernommen; „Abbrechen“ verwirft alles.
struct ProfileFormSheet: View {
    enum Mode {
        case add
        case edit(TikTokProfile)
    }

    /// Unveränderlicher Stand des Profils beim Öffnen des Formulars.
    private struct OriginalProfile {
        let id: UUID
        let username: String
        let manualDisplayName: String
        let autoDisplayName: String?
        let imageFileName: String?
        let imageSource: ProfileImageSource?
    }

    @Environment(ProfileListController.self) private var controller
    @Environment(\.dismiss) private var dismiss

    private let original: OriginalProfile?

    @State private var linkText: String
    @State private var manualName: String
    @State private var imageChange: ProfileImageChange = .unchanged
    @State private var pickedPreview: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isLinkFocused: Bool

    init(mode: Mode) {
        switch mode {
        case .add:
            original = nil
            _linkText = State(initialValue: "")
            _manualName = State(initialValue: "")
        case .edit(let profile):
            original = OriginalProfile(
                id: profile.id,
                username: profile.username,
                manualDisplayName: profile.manualDisplayName ?? "",
                autoDisplayName: profile.autoDisplayName,
                imageFileName: profile.localImageFileName,
                imageSource: profile.imageSource
            )
            _linkText = State(initialValue: profile.profileURLString)
            _manualName = State(initialValue: profile.manualDisplayName ?? "")
        }
    }

    private var isEditing: Bool { original != nil }

    private var trimmedLink: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasManualImageInDraft: Bool {
        switch imageChange {
        case .setManual:
            return true
        case .resetManual:
            return false
        case .unchanged:
            return original?.imageSource == .manual && original?.imageFileName != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                linkSection
                if isEditing {
                    displayNameSection
                    imageSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(DemonicBackground())
            .navigationTitle(isEditing ? "Profil bearbeiten" : "Profil hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Wird gespeichert")
                    } else {
                        Button("Speichern", action: startSave)
                            .fontWeight(.semibold)
                            .disabled(trimmedLink.isEmpty || isProcessingImage)
                    }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedImage(newItem) }
            }
            .onAppear {
                if !isEditing {
                    isLinkFocused = true
                }
            }
        }
        .tint(Theme.blurple)
    }

    // MARK: - Abschnitte

    private var linkSection: some View {
        Section {
            TextField(
                "TikTok-Profillink",
                text: $linkText,
                prompt: Text("https://www.tiktok.com/@username")
            )
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isLinkFocused)
            .accessibilityIdentifier("profileLinkField")
            .onSubmit(startSave)
            .onChange(of: linkText) { _, _ in errorMessage = nil }
            .disabled(isSaving)
            .listRowBackground(Theme.card)
        } header: {
            Text("TikTok-Profillink")
        } footer: {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                    .accessibilityLabel("Fehler: \(errorMessage)")
            } else if isSaving {
                Text("Link wird geprüft …")
            } else {
                Text("Beispiel: https://www.tiktok.com/@username")
            }
        }
    }

    private var displayNameSection: some View {
        Section {
            TextField(
                "Anzeigename",
                text: $manualName,
                prompt: Text(original?.autoDisplayName ?? "Anzeigename (optional)")
            )
            .textInputAutocapitalization(.words)
            .disabled(isSaving)
            .listRowBackground(Theme.card)
        } header: {
            Text("Anzeigename")
        } footer: {
            Text("Leer lassen, um den automatisch geladenen Namen zu verwenden.")
        }
    }

    private var imageSection: some View {
        Section {
            HStack(spacing: 16) {
                imagePreview

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(hasManualImageInDraft ? "Anderes Bild wählen" : "Eigenes Bild wählen", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isSaving || isProcessingImage)

                    if hasManualImageInDraft {
                        Button(role: .destructive) {
                            imageChange = .resetManual
                            pickedPreview = nil
                            pickerItem = nil
                        } label: {
                            Label("Manuelle Auswahl zurücksetzen", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isSaving)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.card)
        } header: {
            Text("Profilbild")
        } footer: {
            Text("Ein eigenes Bild wird bei automatischen Aktualisierungen nicht überschrieben.")
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        ZStack {
            switch imageChange {
            case .setManual:
                ProfileAvatarView(fileName: nil, overrideImage: pickedPreview, size: 64)
            case .resetManual:
                ProfileAvatarView(fileName: nil, size: 64)
            case .unchanged:
                ProfileAvatarView(fileName: original?.imageFileName, size: 64)
            }
            if isProcessingImage {
                ProgressView()
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Aktionen

    private func cancel() {
        saveTask?.cancel()
        dismiss()
    }

    private func startSave() {
        guard !isSaving, !trimmedLink.isEmpty, !isProcessingImage else { return }
        saveTask = Task { await save() }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let link = try await controller.resolveLink(linkText)
            // Wurde das Sheet währenddessen abgebrochen, darf nichts gespeichert werden.
            guard !Task.isCancelled else { return }

            if let original {
                let usernameChanged = link.username != original.username
                let trimmedName = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                let nameWasEdited = trimmedName != original.manualDisplayName
                // Bei einem anderen Profil wird ein unverändert übernommener alter Name verworfen.
                let newManualName: String? = (usernameChanged && !nameWasEdited) || trimmedName.isEmpty
                    ? nil
                    : trimmedName
                try controller.applyEdit(
                    to: original.id,
                    link: link,
                    manualDisplayName: newManualName,
                    imageChange: imageChange
                )
            } else {
                try controller.addProfile(link)
            }
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Das Profil konnte nicht gespeichert werden."
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        isProcessingImage = true
        defer { isProcessingImage = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let processed = await ImageProcessing.downsampledJPEGInBackground(from: data),
              let preview = UIImage(data: processed) else {
            errorMessage = "Das ausgewählte Bild konnte nicht geladen werden."
            return
        }
        // Nur übernehmen, wenn in der Zwischenzeit kein anderes Bild gewählt wurde.
        guard item == pickerItem else { return }
        pickedPreview = preview
        imageChange = .setManual(processed)
    }
}
