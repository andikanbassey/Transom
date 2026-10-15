import AppKit

/// AppleScript commands (see Transom.sdef). They run on the main thread and go through Automation, so the same rules apply.
class TransomScriptCommand: NSScriptCommand {
    func run() throws -> Any? { nil }

    override func performDefaultImplementation() -> Any? {
        do { return try run() } catch {
            scriptErrorNumber = -1
            scriptErrorString = error.localizedDescription
            return nil
        }
    }

    var source: AutomationSource {
        let pid = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        return AutomationSource(pid: pid)
    }
    var number: Int { (directParameter as? Int) ?? Int("\(directParameter ?? "")") ?? 0 }
    var plain: Bool { (evaluatedArguments?["plain"] as? Bool) ?? false }
    func perform(_ action: AutomationAction) throws -> Any? { try Automation.shared.perform(action, source: source); return nil }
}

@objc(TransomClipCountCommand) final class TransomClipCountCommand: TransomScriptCommand {
    override func run() throws -> Any? {
        guard Automation.shared.enabled else { throw AutomationError.disabled }
        return AppModel.shared.clipboard.clips.count
    }
}
@objc(TransomGetClipTextCommand) final class TransomGetClipTextCommand: TransomScriptCommand {
    override func run() throws -> Any? {
        guard Automation.shared.enabled else { throw AutomationError.disabled }
        let clip = try Automation.shared.item(number)
        switch clip.kind {
        case .text: return clip.text ?? ""
        case .file: return (clip.paths ?? []).joined(separator: "\n")
        case .image: return clip.imageURL?.path ?? ""
        }
    }
}
@objc(TransomCopyClipCommand) final class TransomCopyClipCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.copy(number, plain: plain)) }
}
@objc(TransomPasteClipCommand) final class TransomPasteClipCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.paste(number, plain: plain)) }
}
@objc(TransomPinClipCommand) final class TransomPinClipCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.pin(number)) }
}
@objc(TransomPauseCommand) final class TransomPauseCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.pause) }
}
@objc(TransomResumeCommand) final class TransomResumeCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.resume) }
}
@objc(TransomNewNoteCommand) final class TransomNewNoteCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.newNote("\(directParameter ?? "")")) }
}
@objc(TransomSearchCommand) final class TransomSearchCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.search("\(directParameter ?? "")")) }
}
@objc(TransomOpenCommand) final class TransomOpenCommand: TransomScriptCommand {
    override func run() throws -> Any? { try perform(.open) }
}
