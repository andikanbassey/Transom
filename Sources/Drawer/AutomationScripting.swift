import AppKit

/// AppleScript commands (see Drawer.sdef). They run on the main thread and go through Automation, so the same rules apply.
class DrawerScriptCommand: NSScriptCommand {
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

@objc(DrawerClipCountCommand) final class DrawerClipCountCommand: DrawerScriptCommand {
    override func run() throws -> Any? {
        guard Automation.shared.enabled else { throw AutomationError.disabled }
        return AppModel.shared.clipboard.clips.count
    }
}
@objc(DrawerGetClipTextCommand) final class DrawerGetClipTextCommand: DrawerScriptCommand {
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
@objc(DrawerCopyClipCommand) final class DrawerCopyClipCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.copy(number, plain: plain)) }
}
@objc(DrawerPasteClipCommand) final class DrawerPasteClipCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.paste(number, plain: plain)) }
}
@objc(DrawerPinClipCommand) final class DrawerPinClipCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.pin(number)) }
}
@objc(DrawerPauseCommand) final class DrawerPauseCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.pause) }
}
@objc(DrawerResumeCommand) final class DrawerResumeCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.resume) }
}
@objc(DrawerNewNoteCommand) final class DrawerNewNoteCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.newNote("\(directParameter ?? "")")) }
}
@objc(DrawerSearchCommand) final class DrawerSearchCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.search("\(directParameter ?? "")")) }
}
@objc(DrawerOpenCommand) final class DrawerOpenCommand: DrawerScriptCommand {
    override func run() throws -> Any? { try perform(.open) }
}
