import Foundation

let enabledKey = "enabled"

/// What you can change in the Settings window. Saved in UserDefaults.
struct Settings: Codable, Equatable {
    var threshold = 50.0            // % of one core
    var sustainSeconds = 60         // how long a job must stay busy before it is slowed
    var protectedApps: [String] = []
    var observeOnly = false          // report what would be slowed, change nothing
    var language: AppLanguage = .system
    var adminActions = false         // allow the few changes that ask for your administrator password (remove a driver, switch a daemon)

    init() {}

    /// Tolerant: a settings file saved by an older version (missing newer fields) keeps what it has and defaults the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        threshold = try c.decodeIfPresent(Double.self, forKey: .threshold) ?? 50
        sustainSeconds = try c.decodeIfPresent(Int.self, forKey: .sustainSeconds) ?? 60
        protectedApps = try c.decodeIfPresent([String].self, forKey: .protectedApps) ?? []
        observeOnly = try c.decodeIfPresent(Bool.self, forKey: .observeOnly) ?? false
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        adminActions = try c.decodeIfPresent(Bool.self, forKey: .adminActions) ?? false
    }

    private static let key = "settings"

    static func load() -> Settings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s.clamped()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func clamped() -> Settings {
        var s = self
        s.threshold = min(max(threshold, 20), 95)
        s.sustainSeconds = min(max(sustainSeconds, 30), 600)
        s.protectedApps = protectedApps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return s
    }

    var config: Config {
        var c = Config()
        c.threshold = threshold
        c.sustain = max(1, Int((Double(sustainSeconds) / c.interval).rounded(.up)))
        c.dryRun = observeOnly
        return c
    }
}
