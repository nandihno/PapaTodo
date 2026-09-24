import SwiftUI

/// Profile, avatar URL, theme color, and sign-out (specification.md section 9.10).
struct SettingsView: View {
    let user: AppSessionRecord
    let store: ProfileStore
    let onSignOut: () -> Void

    @Environment(PushRegistrationModel.self) private var push
    @Environment(FavouritesStore.self) private var favourites
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var avatarDraft: String?
    @State private var themeDraft: String?

    private var savedAvatar: String { store.profile?.avatarURL?.absoluteString ?? "" }
    private var avatarText: String { avatarDraft ?? savedAvatar }
    private var parsedAvatar: URL?? { AvatarURL.parse(avatarText) }
    private var avatarIsValid: Bool { parsedAvatar != nil }
    private var canSaveAvatar: Bool {
        guard let parsed = parsedAvatar else { return false }
        return (parsed?.absoluteString ?? "") != savedAvatar && store.avatarSave != .saving
    }
    private var displayName: String { store.profile?.fullName ?? user.email ?? "Papa Todos" }

    private var themeText: String { themeDraft ?? store.savedThemeHex }
    private var normalizedTheme: String? { ThemeColor.normalize(themeText) }
    private var canSaveTheme: Bool {
        guard let hex = normalizedTheme else { return false }
        return hex != store.savedThemeHex && store.themeSave != .saving
    }

    var body: some View {
        Form {
            profileSection
            avatarSection
            themeSection
            favouritesSection
            notificationsSection
            Section {
                Button("Sign Out", role: .destructive, action: onSignOut)
                    .accessibilityIdentifier("settings.signOut")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.discardThemePreview() }
        .task { await push.refreshAuthorization() }
        // The user may have changed the permission in the system Settings app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await push.refreshAuthorization() } }
        }
    }

    // MARK: favourites

    private var favouritesSection: some View {
        Section {
            NavigationLink(value: MainRoute.favourites) {
                LabeledContent {
                    if !favourites.templates.isEmpty { Text("\(favourites.templates.count)") }
                } label: {
                    Label("Favourite Chores", systemImage: "star")
                }
            }
            .accessibilityIdentifier("settings.favourites")
        } footer: {
            Text("Chores you make often, shared with the family. Pick one when you add a chore instead of typing it again.")
        }
    }

    // MARK: notifications

    private var notificationsSection: some View {
        Section {
            switch push.authorization {
            case .notDetermined:
                Text("Get a notification when a chore is assigned to you, changed, commented on, or completed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await push.enableNotifications() }
                } label: {
                    Label("Turn On Notifications", systemImage: "bell.badge")
                }
                .disabled(push.isRequestingPermission)
                .accessibilityIdentifier("settings.enableNotifications")
            case .denied:
                Label("Notifications are turned off for Papa Todos.", systemImage: "bell.slash")
                    .accessibilityIdentifier("settings.notificationsStatus")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("settings.openSystemSettings")
            case .authorized:
                Label("Notifications are on.", systemImage: "bell.fill")
                    .accessibilityIdentifier("settings.notificationsStatus")
                switch push.registration {
                case .notRegistered:
                    EmptyView()
                case .registering:
                    ProgressView("Registering this device…")
                case .registered:
                    Label("This device is registered.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .accessibilityIdentifier("settings.deviceRegistered")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Button("Try Again") { Task { await push.retry() } }
                        .accessibilityIdentifier("settings.retryRegistration")
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    // MARK: profile

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                ProfileAvatarView(
                    name: displayName,
                    url: (parsedAvatar ?? nil) ?? store.profile?.avatarURL,
                    size: 56
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName).font(.headline)
                    if let email = user.email {
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if let error = store.loadError {
                Text(error.errorDescription ?? "").font(.footnote).foregroundStyle(.red)
            }
        }
    }

    // MARK: avatar

    private var avatarSection: some View {
        Section {
            TextField("Image URL (https://…)", text: Binding(
                get: { avatarText },
                set: { avatarDraft = $0; store.clearAvatarStatus() }
            ))
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("settings.avatarField")

            if !avatarIsValid {
                Label("Enter a valid http or https image URL.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.avatarError")
            }

            Button("Save Avatar") {
                Task { await store.saveAvatar(avatarText); if store.avatarSave != .saving, case .saved = store.avatarSave { avatarDraft = nil } }
            }
            .disabled(!canSaveAvatar)
            .accessibilityIdentifier("settings.saveAvatar")

            if !savedAvatar.isEmpty {
                Button("Remove Avatar", role: .destructive) {
                    Task { await store.saveAvatar(""); avatarDraft = nil }
                }
                .disabled(store.avatarSave == .saving)
            }
            statusRow(store.avatarSave)
        } header: {
            Text("Avatar")
        } footer: {
            Text("Leave empty and save to use your initials.")
        }
    }

    // MARK: theme

    private var themeSection: some View {
        Section {
            ColorPicker("Accent color", selection: Binding(
                get: { Color(hex: normalizedTheme ?? store.savedThemeHex) },
                set: { if let hex = $0.hexString { choose(hex) } }
            ), supportsOpacity: false)

            TextField("Hex color", text: Binding(
                get: { themeText },
                set: { value in
                    themeDraft = value.uppercased()
                    if let hex = ThemeColor.normalize(value) { store.previewTheme(hex) }
                }
            ))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .accessibilityIdentifier("settings.themeField")

            if normalizedTheme == nil {
                Label("Choose a valid accent color.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            swatches

            let previewHex = normalizedTheme ?? store.savedThemeHex
            Text("Preview")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .foregroundStyle(ThemeColor.readableForegroundIsLight(on: previewHex) ? Color.white : Color(hex: "#0F1311"))
                .background(Color(hex: previewHex), in: Capsule())
                .accessibilityLabel("Preview of \(previewHex)")

            Button("Save Theme") { Task { await store.saveTheme(themeText); if case .saved = store.themeSave { themeDraft = nil } } }
                .disabled(!canSaveTheme)
                .accessibilityIdentifier("settings.saveTheme")
            statusRow(store.themeSave)
        } header: {
            Text("Theme")
        } footer: {
            Text("Very pale or very dark colors keep the default color on buttons so they stay readable; the preview above always uses readable text.")
        }
    }

    private var swatches: some View {
        HStack(spacing: 12) {
            ForEach(ThemeColor.suggestedHexes, id: \.self) { hex in
                Button { choose(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 44, height: 44)
                        .overlay {
                            if normalizedTheme == hex {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(ThemeColor.readableForegroundIsLight(on: hex) ? Color.white : Color(hex: "#0F1311"))
                            }
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Use \(hex)")
                .accessibilityAddTraits(normalizedTheme == hex ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested theme colors")
    }

    private func choose(_ hex: String) {
        themeDraft = hex
        store.previewTheme(hex)
    }

    @ViewBuilder
    private func statusRow(_ state: ProfileStore.SaveState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            ProgressView()
        case .saved(let message):
            Label(message, systemImage: "checkmark.circle.fill").font(.footnote)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
        }
    }
}
