import AppKit
import SwiftUI

/// The choices on the welcome screen. Nothing is applied until "Get started" (except the language, which is harmless and applies at once).
final class FirstRunDraft: ObservableObject {
    @Published var observeOnly = true       // recommended: look first, change nothing
    @Published var openAtLogin = false      // off unless you tick it; turning it on may need approval in System Settings
}

struct FirstRunView: View {
    @ObservedObject var draft: FirstRunDraft
    @ObservedObject var model: AppModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LanguagePicker(model: model).labelsHidden().frame(width: 150).accessibilityLabel(tr("Language"))
            }
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                Text(tr("Keep background jobs from slowing your Mac"))
                    .font(.title2.bold()).multilineTextAlignment(.center)
                Text(tr("BG Optimizer sits in your menu bar and lowers the priority of busy jobs you are not using."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                promise("macwindow", tr("Never touches what you are using"), tr("The app in front of you, and everything inside it, is left alone."))
                promise("checkmark.shield", tr("Leaves the important things alone"), tr("System, calls, audio, browsers, security tools and local AI are protected."))
                promise("arrow.uturn.backward.circle", tr("Always reversible"), tr("It never kills anything. Turn it off or quit and every job returns to normal."))
            }
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("HOW SHOULD IT START?")).font(.caption2.bold()).foregroundStyle(.secondary)
                choice(true, tr("Observe only"), recommended: true, tr("For a while it only lists, in the Activity window, what it would slow. Nothing changes."))
                choice(false, tr("Start optimizing now"), recommended: false, tr("Busy background jobs are slowed right away."))
            }
            .padding(.top, 16)

            Toggle(tr("Launch at login"), isOn: $draft.openAtLogin).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)
            Button(action: onStart) { Text(tr("Get started")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Text(tr("You can change all of this later in Settings.")).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
        .frame(width: 540, height: 700)
    }

    private func promise(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundColor(.accentColor).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choice(_ observe: Bool, _ title: String, recommended: Bool, _ text: String) -> some View {
        let selected = draft.observeOnly == observe
        return Button { draft.observeOnly = observe } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? .accentColor : .secondary).font(.title3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).fontWeight(.semibold)
                        if recommended { Text(tr("Recommended")).font(.caption.bold()).foregroundColor(.accentColor) }
                    }
                    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(tr("Choose how it starts"))
    }
}
