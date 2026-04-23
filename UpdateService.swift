#if os(macOS) && canImport(Sparkle)
import Foundation
import Combine
import Sparkle

/// Sparkle-based in-app update flow. Replaces the old "download DMG and drag"
/// experience: Sparkle handles download, EdDSA signature verification, quit,
/// install-in-place, and relaunch in one flow.
///
/// Guarded by `canImport(Sparkle)` so the app still builds if the SPM dependency
/// hasn't been added yet. Add via Xcode → File → Add Package Dependencies… →
/// https://github.com/sparkle-project/Sparkle (pin to the latest 2.x).
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    let updaterController: SPUStandardUpdaterController
    @Published var canCheckForUpdates: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
#endif
