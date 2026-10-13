import AppKit
import SwiftUI

/// Tiny holder for view-local text. (@State needs a compiler macro plugin that only Xcode ships.)
final class TextBox: ObservableObject { @Published var text = "" }

struct SettingsActions {
    var setLogin: (Bool) -> Void
    var giveBack: () -> Void
}

/// Language names are always shown in their own language, so you can find yours even when the app is in the wrong one.
struct LanguagePicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Picker(tr("Language"), selection: $model.settings.language) {
            Text(tr("System default")).tag(AppLanguage.system)
            Text("English").tag(AppLanguage.english)
            Text("Українська").tag(AppLanguage.ukrainian)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let actions: SettingsActions

    var body: some View {
        TabView {
            GeneralTab(model: model, actions: actions).tabItem { Label(tr("General"), systemImage: "speedometer") }
            ProtectedTab(model: model).tabItem { Label(tr("Protected apps"), systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 560)
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    let actions: SettingsActions
    private let cores = ProcessInfo.processInfo.processorCount

    var body: some View {
        Form {
            Section {
                Toggle(tr("Optimize background jobs"), isOn: $model.enabled)
                Toggle(tr("Launch at login"), isOn: Binding(get: { model.loginEnabled }, set: { actions.setLogin($0) }))
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(tr("Observe only"), isOn: $model.settings.observeOnly)
                    Text(tr("Report what would be slowed in the log, but change nothing."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                LanguagePicker(model: model)
            }
            Section(tr("Sensitivity")) {
                VStack(alignment: .leading) {
                    Text(tr("Slow a job when it uses more than %d%% of one core", Int(model.settings.threshold)))
                    Slider(value: $model.settings.threshold, in: 20...95, step: 5)
                    Text(tr("100%% is one full core. Cores in this Mac: %d. Lower values act sooner.", cores))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker(tr("…and keeps doing it for"), selection: $model.settings.sustainSeconds) {
                    Text(trPlural("seconds", 30)).tag(30)
                    Text(trPlural("minutes", 1)).tag(60)
                    Text(trPlural("minutes", 2)).tag(120)
                    Text(trPlural("minutes", 5)).tag(300)
                }
            }
            Section(tr("Right now")) {
                if !model.enabled {
                    Text(tr("Switched off. Nothing is being slowed.")).foregroundStyle(.secondary)
                } else if model.slowed.isEmpty {
                    Text(tr("Nothing slowed down.")).foregroundStyle(.secondary)
                } else {
                    ForEach(model.slowed, id: \.pid) { Text(tr("%@  (pid %d)", $0.name, Int($0.pid))) }
                    Button(tr("Give everything back now"), action: actions.giveBack)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProtectedTab: View {
    @ObservedObject var model: AppModel
    @StateObject private var draft = TextBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Apps listed here are never slowed down, on top of the built-in protections (system, browsers, calls, audio, security tools, local AI, code editors, terminals)."))
                .font(.callout).foregroundStyle(.secondary)
            List {
                if model.settings.protectedApps.isEmpty {
                    Text(tr("No extra apps yet.")).foregroundStyle(.secondary)
                }
                ForEach(model.settings.protectedApps, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button { model.settings.protectedApps.removeAll { $0 == name } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help(tr("Remove"))
                            .accessibilityLabel(tr("Remove"))
                    }
                }
            }
            HStack {
                TextField(tr("App name, e.g. HandBrake"), text: $draft.text).onSubmit(add)
                Button(tr("Add"), action: add).disabled(draft.text.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(tr("Choose app…"), action: choose)
            }
        }
        .padding()
    }

    private func add() {
        let n = draft.text.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty, !model.settings.protectedApps.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) {
            model.settings.protectedApps.append(n)
        }
        draft.text = ""
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.text = url.deletingPathExtension().lastPathComponent
            add()
        }
    }
}
