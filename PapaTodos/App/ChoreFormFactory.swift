import Foundation

/// Builds the create/edit form's model from the app's services, so Home and the detail screen
/// present the same form without each knowing how to wire it.
@MainActor
struct ChoreFormFactory {
    let environment: AppEnvironment
    let session: AppSession

    func makeModel(mode: ChoreFormModel.Mode) -> ChoreFormModel {
        ChoreFormModel(
            mode: mode,
            saveService: ChoreSaveService(
                chores: environment.choreRepository, attachments: environment.attachmentRepository, storage: environment.attachmentStorage
            ),
            deleteService: ChoreDeleteService(chores: environment.choreRepository, storage: environment.attachmentStorage),
            profiles: environment.profileRepository,
            onSessionExpired: { [weak session] in session?.handleSessionExpired() }
        )
    }
}
