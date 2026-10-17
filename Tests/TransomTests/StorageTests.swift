import Foundation
import Testing
@testable import Transom

/// The Markdown history format is what people's data is stored in, so reading what was written must give the same items back.
@Suite struct HistoryFormatTests {
    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test func roundTripKeepsEveryField() {
        var text = Clip(kind: .text)
        text.text = "Meeting notes\nsecond line"
        text.sourceApp = "Notes"
        text.sourceBundleID = "com.apple.Notes"
        text.date = date(1_792_000_000)
        text.modified = date(1_792_000_100)
        text.pinned = true

        var picture = Clip(kind: .image)
        picture.imageFile = "ABCD.png"
        picture.date = date(1_792_000_500)
        picture.modified = picture.date

        var files = Clip(kind: .file)
        files.paths = ["/Users/someone/Desktop/Brand colours.txt", "/tmp/a.png"]
        files.date = date(1_792_001_000)
        files.modified = files.date

        let parsed = ClipHistoryFile.parse(ClipHistoryFile.render(month: "2026-10", clips: [text, picture, files]))

        #expect(parsed.count == 3)
        let byID = Dictionary(uniqueKeysWithValues: parsed.map { ($0.id, $0) })
        #expect(byID[text.id]?.text == "Meeting notes\nsecond line")
        #expect(byID[text.id]?.pinned == true)
        #expect(byID[text.id]?.sourceBundleID == "com.apple.Notes")
        #expect(byID[text.id]?.date == text.date)
        #expect(byID[text.id]?.modified == text.modified)
        #expect(byID[picture.id]?.kind == .image)
        #expect(byID[picture.id]?.imageFile == "ABCD.png")
        #expect(byID[files.id]?.paths == files.paths)
    }

    @Test func textThatLooksLikeAMarkerSurvives() {
        var tricky = Clip(kind: .text)
        tricky.text = "before\n<!-- /drawer:clip -->\n<!-- drawer:clip {\"id\":\"x\"} -->\nafter"
        tricky.date = date(1_792_002_000)
        tricky.modified = tricky.date

        let parsed = ClipHistoryFile.parse(ClipHistoryFile.render(month: "2026-10", clips: [tricky]))

        #expect(parsed.count == 1)
        #expect(parsed.first?.text == tricky.text)
    }

    @Test func emptyAndUnknownTextGivesNoItems() {
        #expect(ClipHistoryFile.parse("").isEmpty)
        #expect(ClipHistoryFile.parse("# Clipboard 2026-10\n\nnot a clip at all\n").isEmpty)
    }
}

/// The updater offers a release only when its version is newer than the running one.
@Suite struct VersionTests {
    @Test func newerVersionsAreOffered() {
        #expect(Updater.isNewer("0.7", than: "0.6.0"))
        #expect(Updater.isNewer("0.7.1", than: "0.7.0"))
        #expect(Updater.isNewer("1.0", than: "0.9.9"))
        #expect(Updater.isNewer("0.10", than: "0.9"))
    }

    @Test func sameOrOlderVersionsAreNot() {
        #expect(!Updater.isNewer("0.7", than: "0.7.0"))
        #expect(!Updater.isNewer("0.6", than: "0.7.0"))
        #expect(!Updater.isNewer("0.7.0", than: "0.7.1"))
    }
}

/// Secrets are masked even when the app that copied them did not flag them.
@Suite struct SecretTests {
    @Test func recognisesCommonSecrets() {
        #expect(SecretPatterns.looksSecret("ghp_" + String(repeating: "a1B2", count: 10)))
        #expect(SecretPatterns.looksSecret("sk-ant-api03-" + String(repeating: "x", count: 30)))
        #expect(SecretPatterns.looksSecret("AKIAABCDEFGHIJKLMNOP"))
        #expect(SecretPatterns.looksSecret("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----"))
        #expect(SecretPatterns.looksSecret("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"))
    }

    @Test func leavesOrdinaryTextAlone() {
        #expect(!SecretPatterns.looksSecret("Meeting notes: send the invoice on Friday"))
        #expect(!SecretPatterns.looksSecret("https://github.com/andikanbassey/Transom"))
        #expect(!SecretPatterns.looksSecret("#4F46E5"))
        #expect(!SecretPatterns.looksSecret(""))
    }

    @Test func aSensitiveClipHidesItsText() {
        var clip = Clip(kind: .text)
        clip.text = "correct horse battery staple"
        clip.sensitive = true
        #expect(clip.title == "Sensitive item")
        #expect(!clip.title.contains("horse"))
        #expect(clip.kindLabel == "Sensitive")
    }
}

/// A save must never delete the month file it has just written, however the folder path is spelled.
@Suite struct FolderPathTests {
    @Test func symlinkedPathIsTheSameFile() throws {
        let name = "transom-test-\(UUID().uuidString).md"
        let viaSymlink = URL(fileURLWithPath: "/tmp/" + name)
        try "x".write(to: viaSymlink, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: viaSymlink) }
        #expect(ClipboardFolder.sameFile(viaSymlink, URL(fileURLWithPath: "/private/tmp/" + name)))
    }

    @Test func differentFilesAreNot() {
        #expect(!ClipboardFolder.sameFile(URL(fileURLWithPath: "/tmp/Clipboard/2026-10.md"),
                                          URL(fileURLWithPath: "/tmp/Clipboard/2026-10 2.md")))
    }
}
