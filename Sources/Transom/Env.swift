import Foundation

/// Debug and test switches read from the environment. `TRANSOM_<NAME>` is the name; the old `DRAWER_<NAME>` still works.
enum Env {
    static subscript(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["TRANSOM_" + name] ?? env["DRAWER_" + name]
    }

    /// True when any switch is set (snapshots, tests, a scratch data folder). Such runs never stop to ask questions.
    /// `GUARD_CHOICE` answers the two-copies question, so it does not count.
    static var hasTestSwitch: Bool {
        ProcessInfo.processInfo.environment.keys.contains {
            ($0.hasPrefix("TRANSOM_") || $0.hasPrefix("DRAWER_")) && !$0.hasSuffix("_GUARD_CHOICE")
        }
    }
}
