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
