import Foundation

/// State shared by the menu and the Settings window.
final class AppModel: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: enabledKey)
            onEnabled?(enabled)
        }
    }
    @Published var settings: Settings {
        didSet { settings.save(); onSettings?(settings) }
    }
    @Published var slowed: [Slowed] = []
    @Published var loginEnabled = false

    var onEnabled: ((Bool) -> Void)?
    var onSettings: ((Settings) -> Void)?

    /// For previews and snapshots only: does not touch saved settings.
    init(previewEnabled: Bool, observeOnly: Bool = false, slowed: [Slowed] = []) {
        enabled = previewEnabled
        settings = Settings()
        settings.observeOnly = observeOnly
        self.slowed = slowed
    }

    init() {
        enabled = UserDefaults.standard.bool(forKey: enabledKey)      // off until you switch it on
        settings = Settings.load()
    }
}
