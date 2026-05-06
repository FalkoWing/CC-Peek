import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController {
    static let shared = SoftwareUpdateController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func start() {
        // Touching the singleton starts Sparkle via `startingUpdater: true`.
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
