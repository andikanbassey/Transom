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

@Suite struct HistoryLoadingTests {
    private func text(_ body: String, date: Date, pinned: Bool = false, modified: Date? = nil) -> Clip {
        var clip = Clip(kind: .text)
        clip.text = body; clip.date = date; clip.modified = modified ?? date; clip.pinned = pinned
        return clip
    }

    @Test func windowIncludesOldPinsAndExpiredItemsButDefersRestoredItems() {
        let now = Date(), old = Date().addingTimeInterval(-90 * 86400)
        let recent = text("recent", date: now)
        let pin = text("pinned", date: old, pinned: true)
        let expired = text("expired", date: old)
        let restored = text("restored", date: old, modified: now)
        let source = ClipHistoryFile.render(month: "2026-01", clips: [recent, pin, expired, restored])
        let records = ClipHistoryFile.parse(source).map(ClipRecord.init)
        let chosen = ClipRecord.selection(records, limit: 1, cutoff: now.addingTimeInterval(-86400))
        #expect(chosen == Set([recent.id, pin.id, expired.id]))
        #expect(Set(ClipHistoryFile.parse(source, including: chosen).map(\.id)) == chosen)
        #expect(ClipRecord.selection(records, limit: nil, cutoff: nil).count == 4)
    }

    @Test func selectiveReadKeepsMarkdownAndEscapedMarkersExactly() {
        let now = Date()
        var rich = text("bold", date: now)
        rich.markdown = "**bold**\n<!-- /drawer:clip -->\n\\literal"
        let other = text(String(repeating: "unused body", count: 1000), date: now)
        let source = ClipHistoryFile.render(month: "2026-01", clips: [rich, other])
        let parsed = ClipHistoryFile.parse(source, including: [rich.id])
        #expect(parsed.count == 1)
        #expect(parsed.first?.markdown == rich.markdown)
                #expect(ClipHistoryFile.parse(source, including: []).isEmpty)
    }

    @Test func incompleteRecordsNeverEnterTheIndex() {
        let clip = text("hello", date: Date())
        let source = ClipHistoryFile.render(month: "2026-01", clips: [clip])
        let truncated = source.replacingOccurrences(of: "<!-- /drawer:clip -->", with: "")
                #expect(ClipHistoryFile.parse(truncated).isEmpty)
    }

    @Test func metadataCacheInvalidatesChangesAndDoesNotStoreBodies() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("2026-01.md")
        let a = text("private clipboard body 12345", date: Date())
        try ClipHistoryFile.render(month: "2026-01", clips: [a]).write(to: file, atomically: true, encoding: .utf8)
        var cache = ClipboardIndex()
        #expect(cache.records(in: file).map(\.id) == [a.id])
        let encoded = try JSONEncoder().encode(cache)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(a.text!))
        cache = try JSONDecoder().decode(ClipboardIndex.self, from: encoded)
        #expect(cache.records(in: file).map(\.id) == [a.id])
        let b = text("different", date: Date(), pinned: true)
        try ClipHistoryFile.render(month: "2026-01", clips: [b]).write(to: file, atomically: true, encoding: .utf8)
        #expect(cache.records(in: file).map(\.id) == [b.id])
        #expect(cache.records(in: file).first?.pinned == true)
        try FileManager.default.removeItem(at: file)
        cache.keep(only: [])
        #expect(cache.fileCount == 0)
        #expect(cache.records(in: file).isEmpty)
    }

    @Test func identityMatchesPlainTextAndKeepsFileBoundaries() {
        var a = text("body", date: Date())
        var b = a; b.date = .distantPast; b.pinned = true
        #expect(ClipRecord.identity(of: a) == ClipRecord.identity(of: b))
        b.text = "different"
        #expect(ClipRecord.identity(of: a) != ClipRecord.identity(of: b))
        a.kind = .file; b.kind = .file
        a.paths = ["a", "bc"]; b.paths = ["ab", "c"]
        #expect(ClipRecord.identity(of: a) != ClipRecord.identity(of: b))
    }
}

@Suite struct DeferredHistoryTests {
    private func record(_ body: String, app: String) -> ClipRecord {
        var clip = Clip(kind: .text)
        clip.text = body; clip.sourceApp = app
        return ClipRecord(clip)
    }

    @Test func aRepeatCopyTakesTheOlderItemOutOfTheCounts() throws {
        var deferred = DeferredHistory()
        let a = record("a", app: "Notes"), b = record("b", app: "Notes"), c = record("c", app: "Safari")
        for r in [a, b, c] { deferred.add(r, lifetime: nil) }
        #expect(deferred.count == 3)
        #expect(deferred.apps["Notes"]?.count == 2)

        #expect(deferred.take(identity: try #require(a.identity))?.id == a.id)
        #expect(deferred.take(identity: try #require(a.identity)) == nil)
        #expect(deferred.count == 2)
        #expect(deferred.apps["Notes"]?.count == 1)

        _ = deferred.take(identity: try #require(c.identity))
        #expect(deferred.apps["Safari"] == nil)
    }

    @Test func expiryIsTheSoonestItem() {
        var deferred = DeferredHistory()
        var old = Clip(kind: .text); old.date = Date(timeIntervalSince1970: 1000); old.modified = old.date
        var new = Clip(kind: .text); new.date = Date(timeIntervalSince1970: 5000); new.modified = new.date
        deferred.add(ClipRecord(new), lifetime: 10)
        deferred.add(ClipRecord(old), lifetime: 10)
        #expect(deferred.expiry == Date(timeIntervalSince1970: 1010))
    }
}

/// Opt in with TRANSOM_STORAGE_TESTS=1 and a fresh TRANSOM_SUPPORT_DIR; never runs against personal history.
@Suite(.serialized) @MainActor struct HistoryStoreIntegrationTests {
    private func settled(_ store: ClipboardStore) async throws {
        for _ in 0..<500 {
            if !store.loading { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("History loading did not finish")
    }

    @Test(.enabled(if: Env["STORAGE_TESTS"] == "1" && Env["SUPPORT_DIR"]?.hasPrefix("/tmp/transom-storage-") == true))
    func partialSavesSyncRetentionAndRestoreKeepDeferredHistory() async throws {
        // A fresh folder is required so even an incorrectly repeated invocation cannot clear pre-existing files.
        #expect(ClipboardFolder.monthFiles().isEmpty)
        guard ClipboardFolder.monthFiles().isEmpty else { return }
        Settings.shared.v.retention = .forever
        Settings.shared.v.paused = true
        Settings.shared.v.linkPreviews = false
        ClipboardFolder.prepare()
        let now = Date()
        var clips = (0..<600).map { i -> Clip in
            var c = Clip(kind: .text)
            c.text = "fixture \(i)"; c.date = now.addingTimeInterval(-Double(i) * 86400); c.modified = c.date
            return c
        }
        clips[599].pinned = true
        for (month, items) in Dictionary(grouping: clips, by: { ClipboardFolder.monthKey($0.date) }) {
            try ClipHistoryFile.render(month: month, clips: items).write(to: ClipboardFolder.fileURL(month: month), atomically: true, encoding: .utf8)
        }
        let store = ClipboardStore(monitoring: false)
        try await settled(store)
        #expect(store.clips.count == 201)
        #expect(store.totalCount == 600)
        #expect(store.clips.contains { $0.id == clips[599].id })
        #expect(store.hiddenCount == 399)

        // A save containing only recent clips must leave older entries in the same month intact.
        let edge = try #require(store.clips.first { $0.id == clips[199].id })
        store.togglePin(edge)
        store.showOlder()
        try await settled(store)
        #expect(store.totalCount == 600)
        #expect(store.clips.first { $0.id == edge.id }?.pinned == true)
        #expect(store.deferredCount > 0)

        // A deletion arriving through deleted.txt alone must invalidate the history signature.
        ClipboardFolder.addTombstone(clips[10].id)
        store.refreshIfChanged()
        try await settled(store)
        #expect(!store.clips.contains { $0.id == clips[10].id })
        #expect(store.totalCount == 599)

        // Loading must not rewrite deleted.txt when nothing changed: in a synced folder two Macs would wake each other forever.
        let before = ClipboardFolder.fileSignature(ClipboardFolder.deletedFile)
        store.showOlder()
        try await settled(store)
        #expect(ClipboardFolder.fileSignature(ClipboardFolder.deletedFile) == before)

        store.holdFullHistory("test")
        try await settled(store)
        #expect(store.clips.count == 599)
        #expect(store.deferredCount == 0)
        #expect(Set(store.clips.map(\.id)) == Set(clips.map(\.id)).subtracting([clips[10].id]))

        // Expiring items in deferred months must still archive them; old pins survive.
        store.releaseFullHistory("test")
        store.resetWindow()
        try await settled(store)
        #expect(store.deferredCount > 0)
        Settings.shared.v.retention = .day
        try await Task.sleep(for: .milliseconds(30))
        try await settled(store)
        #expect(store.clips.contains { $0.id == clips[599].id })
        #expect(store.clips.contains { $0.id == edge.id })
        store.holdFullHistory("test")
        try await settled(store)
        let beforeRestore = store.clips.count
        var restored: Int?
        store.restoreArchived(.all) { restored = $0 }
        for _ in 0..<500 {
            if restored != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(restored == 599 - beforeRestore)
        #expect(store.clips.count == 599)
        store.trim()
        #expect(store.clips.count == 599)
    }
}


/// Deleting waits a few seconds so it can be undone, and only then writes anything.
@Suite(.serialized) @MainActor struct UndoDeleteIntegrationTests {
    // Its own scratch folder (/tmp/transom-undo-…): run beside the storage suite, the two would write into each other's.
    @Test(.enabled(if: Env["STORAGE_TESTS"] == "1" && Env["SUPPORT_DIR"]?.hasPrefix("/tmp/transom-undo-") == true))
    func undoBringsItemsBackAndCommitRemovesThem() async throws {
        Settings.shared.v.paused = true
        Settings.shared.v.linkPreviews = false
        ClipboardFolder.prepare()
        let store = ClipboardStore(monitoring: false)
        for _ in 0..<500 { if !store.loading { break }; try await Task.sleep(for: .milliseconds(10)) }
        let before = store.clips.count
        var a = Clip(kind: .text); a.text = "undo fixture a \(UUID())"
        var b = Clip(kind: .text); b.text = "undo fixture b \(UUID())"
        store.clips.insert(contentsOf: [a, b], at: 0)
        store.delete(ids: [a.id, b.id])
        #expect(store.clips.count == before)
        #expect(store.undoable?.clips.count == 2)
        store.undoDelete()
        #expect(store.clips.contains { $0.id == a.id } && store.clips.contains { $0.id == b.id })
        #expect(store.undoable == nil)
        store.delete(ids: [a.id])
        store.commitPendingDelete(wait: true)
        #expect(store.undoable == nil)
        #expect(!store.clips.contains { $0.id == a.id })
        #expect(ClipboardFolder.tombstones()[a.id] != nil)
    }
}
