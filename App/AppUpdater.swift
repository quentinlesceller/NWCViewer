import SwiftUI
import Sparkle

/// Sparkle owns scheduling and persists the user's choices across launches.
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false

    init() {
        #if DEBUG
        let start = false // Unit tests and development builds never contact the feed.
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main).assign(to: &$automaticDownloads)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
}

struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                Toggle("Download and install updates automatically", isOn: Binding(get: { updater.automaticDownloads }, set: updater.setAutomaticDownloads))
                    .disabled(!updater.automaticChecks)
            } header: {
                Text("Updates")
            } footer: {
                Text("Updates are checked daily and installed when you quit the app. Your scores stay on your Mac.")
            }
            Button("Check for Updates…", action: updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
    }
}
