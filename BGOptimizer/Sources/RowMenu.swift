import Foundation

/// What a click on the "…" button of a row does. Kept separate from the menu drawing so it can be tested.
enum RowMenuAction {
    case restore
    case slow            // allowed without a warning
    case askToSlow       // show the warning first
    case protect(String)
    case unprotect(String)
    case none
}

enum RowMenuEntry {
    case item(title: String, enabled: Bool, action: RowMenuAction)
    case separator
}

/// The items of a row's menu. Only what is allowed is enabled; a locked job says why. (The engine checks again when you act.)
func rowMenuEntries(_ row: ActivityRow) -> [RowMenuEntry] {
    var out: [RowMenuEntry] = []
    if row.canRestore {
        out.append(.item(title: tr("Restore normal priority"), enabled: true, action: .restore))
    }
    switch row.access {
    case .ok: out.append(.item(title: tr("Slow down now"), enabled: true, action: .slow))
    case .confirm: out.append(.item(title: tr("Slow down now…"), enabled: true, action: .askToSlow))
    case .locked:
        if !row.canRestore {
            // A reason that is already a full instruction ("Turn off Observe only to change jobs") stands alone.
            let instruction = row.lockReason == tr("Turn off Observe only to change jobs") || row.lockReason == tr("Switch the app on to change jobs")
            out.append(.item(title: instruction ? (row.lockReason ?? "") : tr("Cannot change: %@", row.lockReason ?? ""), enabled: false, action: .none))
        }
    }
    if let entry = row.userEntry {
        out.append(.separator)
        out.append(.item(title: tr("Remove “%@” from the protected list", entry), enabled: true, action: .unprotect(entry)))
    } else if row.canProtect {
        out.append(.separator)
        out.append(.item(title: tr("Never slow “%@”", row.protectName), enabled: true, action: .protect(row.protectName)))
    }
    return out
}
