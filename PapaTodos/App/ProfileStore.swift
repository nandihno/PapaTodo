import Foundation
import Observation

/// The signed-in user's own profile: loading it, the unsaved theme preview, and the
/// avatar/theme saves.
///
/// The store is created with the session's user id and only ever reads or writes that
/// row. Row-level security currently lets any signed-in user update any profile
/// (see docs/phase-0-validation.md), so the app enforces "own row only" itself
/// instead of relying on the server.
@Observable
@MainActor
final class ProfileStore {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved(String)
        case failed(String)
    }

    let userID: UUID
    private(set) var profile: Profile?
    private(set) var loadError: DataServiceError?
    private(set) var avatarSave: SaveState = .idle
    private(set) var themeSave: SaveState = .idle
    /// An unsaved color being previewed (applied app-wide, discarded if not saved).
    private(set) var previewThemeHex: String?

    private let repository: any ProfileRepository
    private let onSessionExpired: @MainActor () -> Void

    init(userID: UUID, repository: any ProfileRepository, onSessionExpired: @escaping @MainActor () -> Void = {}) {
        self.userID = userID
        self.repository = repository
        self.onSessionExpired = onSessionExpired
    }

    var savedThemeHex: String { ThemeColor.effectiveHex(profile?.personalisation.theme) }
    /// The color the app should tint with right now: the preview if any, else saved.
    var activeThemeHex: String { previewThemeHex ?? savedThemeHex }

    func load() async {
        do {
            profile = try await repository.fetchProfile(id: userID)
            loadError = nil
        } catch {
            handle(error) { loadError = $0 }
        }
    }

    // MARK: theme

    func previewTheme(_ hex: String) {
        guard let normalized = ThemeColor.normalize(hex) else { return }
        previewThemeHex = normalized == savedThemeHex ? nil : normalized
        themeSave = .idle
    }

    func discardThemePreview() {
        previewThemeHex = nil
    }

    func saveTheme(_ hex: String) async {
        guard let normalized = ThemeColor.normalize(hex) else {
            themeSave = .failed("Choose a valid accent color.")
            return
        }
        guard themeSave != .saving else { return }
        themeSave = .saving
        do {
            profile = try await repository.updateThemeColor(id: userID, to: normalized)
            previewThemeHex = nil
            themeSave = .saved("Theme saved.")
        } catch {
            themeSave = .idle
            handle(error) { themeSave = .failed($0.errorDescription ?? "") }
        }
    }

    // MARK: avatar

    /// Empty input clears the avatar; anything else must be a valid http(s) URL.
    func saveAvatar(_ input: String) async {
        guard let parsed = AvatarURL.parse(input) else {
            avatarSave = .failed("Enter a valid http or https image URL.")
            return
        }
        guard avatarSave != .saving else { return }
        avatarSave = .saving
        do {
            profile = try await repository.updateAvatarURL(id: userID, to: parsed)
            avatarSave = .saved(parsed == nil ? "Avatar cleared." : "Avatar saved.")
        } catch {
            avatarSave = .idle
            handle(error) { avatarSave = .failed($0.errorDescription ?? "") }
        }
    }

    func clearAvatarStatus() {
        avatarSave = .idle
    }

    private func handle(_ error: any Error, assign: (DataServiceError) -> Void) {
        let failure = (error as? DataServiceError) ?? .server
        switch failure {
        case .cancelled:
            break
        case .sessionExpired:
            onSessionExpired()
        default:
            assign(failure)
        }
    }
}
