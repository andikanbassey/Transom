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

/// Clearing unpinned items follows the filters, and a sensitive item's countdown runs from when it became sensitive.
@Suite struct ScopedClearAndSensitiveTests {
    private func clip(_ text: String, app: String, pinned: Bool = false) -> Clip {
        var c = Clip(kind: .text)
        c.text = text
        c.sourceApp = app
        c.sourceBundleID = "com.example." + app
        c.pinned = pinned
        return c
    }

    @Test func filteringByAppKeepsOnlyThatApp() {
        let list = [clip("a", app: "Claude"), clip("b", app: "Claude", pinned: true), clip("c", app: "Dia")]
        let shown = ClipboardStore.filtered(list, filter: .all, time: .any, app: "com.example.Claude", pinnedOnly: false, query: "")
        #expect(shown.map { $0.text } == ["a", "b"])
        // What "Clear Unpinned" removes while Claude is selected: Claude's unpinned item only.
        #expect(shown.filter { !$0.pinned }.map { $0.text } == ["a"])
    }

    @Test func noFilterShowsEverything() {
        let list = [clip("a", app: "Claude"), clip("c", app: "Dia")]
        #expect(ClipboardStore.filtered(list, filter: .all, time: .any, app: nil, pinnedOnly: false, query: "").count == 2)
    }

    @Test func countdownRunsFromWhenItBecameSensitive() {
        var old = clip("secret", app: "Dia")
        old.date = Date().addingTimeInterval(-3 * 3600)          // copied three hours ago, marked just now
        old.sensitive = true
        old.sensitiveSince = Date()
        let left = old.sensitiveExpiry!.timeIntervalSinceNow
        #expect(left > ClipboardStore.sensitiveLifetime - 5 && left <= ClipboardStore.sensitiveLifetime)
        #expect(clip("plain", app: "Dia").sensitiveExpiry == nil)
    }

    @Test func itemWithoutAMarkTimeFallsBackToItsCopyDate() {
        var c = clip("secret", app: "Dia")
        c.sensitive = true
        c.date = Date(timeIntervalSince1970: 1_000)
        #expect(c.sensitiveExpiry == Date(timeIntervalSince1970: 1_000 + ClipboardStore.sensitiveLifetime))
    }

    @Test func dissolveOnlyStartsInTheLastHalfMinute() {
        let now = Date()
        #expect(SensitiveFade.amount(expiry: now.addingTimeInterval(120), now: now) == 0)
        #expect(SensitiveFade.amount(expiry: now.addingTimeInterval(15), now: now) == 0.5)
        #expect(SensitiveFade.amount(expiry: now, now: now) == 1)
        #expect(SensitiveFade.amount(expiry: nil, now: now) == 0)
    }

    @Test func clockFormatsMinutesAndSeconds() {
        #expect(SensitiveClock.format(872) == "14:32")
        #expect(SensitiveClock.format(59.2) == "1:00")
        #expect(SensitiveClock.format(0) == "0:00")
    }

    @Test func aSensitivePictureOffersNoFileToShow() {
        var c = Clip(kind: .image)
        c.imageFile = "ABCD.png"
        #expect(c.imageURL != nil)
        c.sensitive = true
        c.sensitiveAbout = "image"
        #expect(c.imageURL == nil)
        #expect(c.previewURL == nil)
        #expect(c.title == "Sensitive image")
    }
}

/// The drawer draws a window of the history, not all of it.
@Suite struct DrawerWindowTests {
    private func clips(_ n: Int, pinned: Int = 0) -> [Clip] {
        (0..<n).map { i in var c = Clip(kind: .text); c.text = "item \(i)"; c.pinned = i < pinned; return c }
    }

    @Test func keepsEveryPinnedItemAndTheNewestUnpinnedOnes() {
        let list = clips(10, pinned: 2)       // `visible` order: pinned first
        let w = ClipboardStore.window(of: list, limit: 3)
        #expect(w.map { $0.text } == ["item 0", "item 1", "item 2", "item 3", "item 4"])
    }

    @Test func aShortListIsShownWhole() {
        #expect(ClipboardStore.window(of: clips(5), limit: 200).count == 5)
        #expect(ClipboardStore.window(of: [], limit: 200).isEmpty)
    }

    @Test func pinnedItemsAreNeverCutOff() {
        #expect(ClipboardStore.window(of: clips(300, pinned: 250), limit: 10).count == 260)
    }
}

/// Retention moves expired items to a local archive that is emptied after 90 days, instead of losing them at once.
@Suite struct ClipboardArchiveTests {
    private func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transom-archive-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func clipWithPicture(in pictures: URL, name: String) -> Clip {
        var clip = Clip(kind: .image)
        clip.imageFile = name
        try? FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
        try? Data("png".utf8).write(to: pictures.appendingPathComponent(name))
        return clip
    }

    @Test func storeKeepsItemsAndMovesPictures() {
        let archive = scratch(), pictures = scratch()
        defer { try? FileManager.default.removeItem(at: archive); try? FileManager.default.removeItem(at: pictures) }
        var text = Clip(kind: .text); text.text = "old note"
        let picture = clipWithPicture(in: pictures, name: "A.png")

        ClipboardArchive.store([text, picture], in: archive) { pictures.appendingPathComponent($0) }

        let file = try! FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).first { $0.pathExtension == "md" }!
        let parsed = ClipHistoryFile.parse(try! String(contentsOf: file, encoding: .utf8))
        #expect(Set(parsed.map(\.id)) == [text.id, picture.id])
        #expect(FileManager.default.fileExists(atPath: archive.appendingPathComponent("Images/A.png").path))
        #expect(!FileManager.default.fileExists(atPath: pictures.appendingPathComponent("A.png").path))
    }

    @Test func storingTwiceOnOneDayAddsToTheSameFile() {
        let archive = scratch()
        defer { try? FileManager.default.removeItem(at: archive) }
        var a = Clip(kind: .text); a.text = "a"
        var b = Clip(kind: .text); b.text = "b"
        ClipboardArchive.store([a], in: archive)
        ClipboardArchive.store([b], in: archive)

        let files = try! FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }
        #expect(files.count == 1)
        #expect(ClipHistoryFile.parse(try! String(contentsOf: files[0], encoding: .utf8)).count == 2)
    }

    @Test func purgeDeletesOnlyFilesPastTheKeepPeriod() {
        let archive = scratch(), pictures = scratch()
        defer { try? FileManager.default.removeItem(at: archive); try? FileManager.default.removeItem(at: pictures) }
        let now = Date()
        let old = clipWithPicture(in: pictures, name: "OLD.png")
        let recent = clipWithPicture(in: pictures, name: "NEW.png")
        let longAgo = now.addingTimeInterval(-Double(ClipboardArchive.keepDays + 1) * 86400)
        let lately = now.addingTimeInterval(-86400)
        ClipboardArchive.store([old], on: longAgo, in: archive) { pictures.appendingPathComponent($0) }
        ClipboardArchive.store([recent], on: lately, in: archive) { pictures.appendingPathComponent($0) }

        ClipboardArchive.purge(now: now, in: archive)

        let files = try! FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }
        #expect(files.count == 1)
        #expect(!FileManager.default.fileExists(atPath: archive.appendingPathComponent("Images/OLD.png").path))
        #expect(FileManager.default.fileExists(atPath: archive.appendingPathComponent("Images/NEW.png").path))
    }
}

@Suite struct ArchiveRestoreTests {
    private func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transom-restore-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func rangesPickFilesByTheHourTheyWereArchived() {
        let archive = scratch(), pictures = scratch()
        defer { try? FileManager.default.removeItem(at: archive); try? FileManager.default.removeItem(at: pictures) }
        let now = Date()
        var recent = Clip(kind: .text); recent.text = "recent"
        var older = Clip(kind: .text); older.text = "older"
        ClipboardArchive.store([recent], on: now, in: archive)
        ClipboardArchive.store([older], on: now.addingTimeInterval(-20 * 86400), in: archive)

        let counts = ClipboardArchive.counts(now: now, in: archive)
        #expect(counts[.pastHour] == 1)
        #expect(counts[.all] == 2)

        let back = ClipboardArchive.restore(.pastHour, now: now, in: archive, pictures: pictures)
        #expect(back.map(\.id) == [recent.id])
        #expect(ClipboardArchive.counts(now: now, in: archive)[.all] == 1)
    }

    @Test func restoreMovesPicturesBack() {
        let archive = scratch(), pictures = scratch(), source = scratch()
        defer { for u in [archive, pictures, source] { try? FileManager.default.removeItem(at: u) } }
        var clip = Clip(kind: .image); clip.imageFile = "P.png"
        try? Data("x".utf8).write(to: source.appendingPathComponent("P.png"))
        ClipboardArchive.store([clip], in: archive) { source.appendingPathComponent($0) }

        _ = ClipboardArchive.restore(.all, in: archive, pictures: pictures)

        #expect(FileManager.default.fileExists(atPath: pictures.appendingPathComponent("P.png").path))
    }
}
