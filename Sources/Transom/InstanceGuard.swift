import AppKit

/// Two copies of Transom (one in Applications and one somewhere else, say) watch the same shortcut, the same screen edge
/// and the same clipboard, so running two at once makes both open the drawer and both save every copy. When a second
/// one starts it asks which to keep. "Keep Both" leaves this one in standby: it does not capture the clipboard or answer the
/// shortcut and edge until it is made the active one.
enum InstanceGuard {
    private static let bundleIDs = ["com.studioab.drawer"]

    static func others() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        return bundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.processIdentifier != me && !$0.isTerminated }
    }

    private static func names(_ apps: [NSRunningApplication]) -> String {
        let n = Array(Set(apps.map { $0.localizedName ?? "Transom" })).sorted()
        return n.joined(separator: " and ")
    }

    /// Asks what to do when another Transom is already running. Returns true if this one should carry on active.
    static func resolveAtLaunch() -> Bool {
        // Debug runs (snapshots, tests) never stop to ask.
        if Env.hasTestSwitch { return true }
        let running = others()
        guard !running.isEmpty else { return true }
        let other = names(running)
        let sameName = other == Brand.name
        // Debug aid: TRANSOM_GUARD_CHOICE=use-this | use-other | keep-both answers the question without showing it.
        if let choice = Env["GUARD_CHOICE"] {
            switch choice {
            case "use-this": quit(running); return true
            case "use-other": NSApp.terminate(nil); return false
            default: return false
            }
        }
        let alert = NSAlert()
        alert.messageText = "Another copy of \(Brand.name) is already running"
        alert.informativeText = """
            Both copies watch the same shortcut, screen edge and clipboard, so both would react at once. \
            Keep one active so it is clear which one you are using.

            Keep Both leaves this copy waiting in the menu bar: no shortcut, no edge swipe and no clipboard capture \
            until you make it active.
            """
        alert.addButton(withTitle: "Use \(Brand.name)")
        alert.addButton(withTitle: "Quit This One")
        alert.addButton(withTitle: "Keep Both")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            quit(running)
            return true
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
            return false
        default:
            return false
        }
    }

    /// Asks the others to quit and waits a few seconds, then forces whatever is left.
    static func quit(_ apps: [NSRunningApplication]) {
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, apps.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }
}
