import AppKit
import SwiftUI

struct PanelActions {
    var restore: (Int32) -> Void
    var giveBack: () -> Void
    var openSettings: () -> Void
    var openActivity: () -> Void
    var quit: () -> Void
}

/// Pressed-state highlight for the footer rows (no hover, which would need view state).
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(configuration.isPressed ? Color.accentColor.opacity(0.25) : .clear))
            .contentShape(Rectangle())
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    let actions: PanelActions

    private var statusLine: String {
        let n = model.slowed.count
        if !model.enabled { return tr("Paused. Nothing is watched.") }
        if model.settings.observeOnly { return tr("Observing only. Nothing is changed.") }
        return n == 0 ? tr("Watching. Nothing slowed.") : trPlural("Watching. jobs slowed", n)
    }

    /// "1 minute" / "30 seconds", in the form that fits after "for" in the current language.
    private var sustainPhrase: String {
        let t = model.settings.sustainSeconds
        return t % 60 == 0 ? trPlural("for minutes", t / 60) : trPlural("for seconds", t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            Divider().padding(.top, 14).padding(.bottom, 6)
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("BG Optimizer").font(.headline)
                Text(statusLine).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.enabled ? tr("On") : tr("Off")).font(.caption.bold()).foregroundStyle(.secondary)
            Toggle(tr("Optimize background jobs"), isOn: $model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    @ViewBuilder private var content: some View {
        if !model.enabled {
            note(tr("Paused"), tr("Nothing is watched and nothing is changed. Every job runs at normal priority."), system: "pause.circle",
                 bg: Color(nsColor: .controlBackgroundColor), ink: .primary)
        } else if model.settings.observeOnly {
            note(tr("Observing only"), tr("Matching jobs are written to the activity log. Nothing is slowed."), system: "eye",
                 bg: Color(nsColor: .controlBackgroundColor), ink: .primary)
        } else if model.slowed.isEmpty {
            note(tr("Nothing needs slowing down"),
                 tr("Checked every 5 seconds. A job over %d%% of one core for %@ gets low priority.",
                    Int(model.settings.threshold), sustainPhrase),
                 system: "checkmark.circle", bg: .calmBg, ink: .calmInk)
        } else {
            slowedList
        }
    }

    private func note(_ title: String, _ text: String, system: String, bg: Color, ink: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: system).font(.title3).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(text).font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(bg))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
        .padding(.top, 14)
    }

    private var slowedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("SLOWED DOWN NOW")).font(.caption2.bold()).foregroundStyle(.secondary).padding(.top, 14)
            ForEach(model.slowed.prefix(8), id: \.pid) { job in row(job) }
            if model.slowed.count > 8 {
                Text(tr("and %d more in the activity log", model.slowed.count - 8)).font(.caption).foregroundStyle(.secondary)
            }
            Button(tr("Give everything back now"), action: actions.giveBack)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private func row(_ job: Slowed) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.name).fontWeight(.semibold).lineLimit(1).truncationMode(.tail).help(job.name)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .heavy)).accessibilityHidden(true)
                    Text(tr("Low priority")).font(.caption2.bold())
                }
                .foregroundStyle(Color.slowInk)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(Capsule().fill(Color.slowBg))
                Text(detail(job)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(tr("Restore")) { actions.restore(job.pid) }
                .accessibilityLabel(tr("Restore normal priority for %@", job.name))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
    }

    private func detail(_ job: Slowed) -> String {
        var parts: [String] = []
        if let cpu = job.cpu { parts.append(tr("%d%% of one core", cpu)) }
        if let since = job.since {
            parts.append(tr("slowed %@", ago(since)))
        }
        return parts.joined(separator: ", ")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button(action: actions.openSettings) {
                HStack { Text(tr("Settings…")); Spacer(); Text("⌘,").foregroundStyle(.secondary) }
            }.keyboardShortcut(",", modifiers: .command)
            Button(action: actions.openActivity) {
                HStack { Text(tr("Activity…")); Spacer(); Text("⌘Y").foregroundStyle(.secondary) }
            }.keyboardShortcut("y", modifiers: .command)
            Button(action: actions.quit) {
                HStack { Text(tr("Quit BG Optimizer")); Spacer(); Text("⌘Q").foregroundStyle(.secondary) }
            }.keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(RowStyle())
        .padding(.horizontal, -10)
    }
}
