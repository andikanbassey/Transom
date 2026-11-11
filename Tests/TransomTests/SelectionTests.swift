import Foundation
import Testing
@testable import Transom

/// Groups are stored in the history files, and ⇧-click and drag-select pick runs of items: both must stay right.
@Suite struct SelectionAndGroupTests {
    @Test func groupSurvivesTheHistoryFile() {
        var grouped = Clip(kind: .text)
        grouped.text = "Thanks, speak soon"
        grouped.pinned = true
        grouped.group = "Replies"
        var stale = Clip(kind: .text)
        stale.text = "not pinned any more"
        stale.group = "Replies"
        let parsed = ClipHistoryFile.parse(ClipHistoryFile.render(month: "2026-11", clips: [grouped, stale]))
        let byID = Dictionary(uniqueKeysWithValues: parsed.map { ($0.id, $0) })
        #expect(byID[grouped.id]?.group == "Replies")
        #expect(byID[grouped.id]?.pinGroup == "Replies")
        // A group only means something on a pin, so an unpinned item does not keep one.
        #expect(byID[stale.id]?.group == nil)
    }

    @Test func runGoesEitherWay() {
        let ids = (0..<5).map { _ in UUID() }
        #expect(ClipboardStore.run(from: ids[1], to: ids[3], in: ids) == Array(ids[1...3]))
        #expect(ClipboardStore.run(from: ids[4], to: ids[2], in: ids) == Array(ids[2...4]))
        #expect(ClipboardStore.run(from: ids[2], to: ids[2], in: ids) == [ids[2]])
        #expect(ClipboardStore.run(from: UUID(), to: ids[2], in: ids) == nil)
    }

    @Test func pinsAreOrderedByGroup() {
        func pin(_ group: String?) -> Clip { var c = Clip(kind: .text); c.text = group ?? "plain"; c.pinned = true; c.group = group; return c }
        let list = [pin("B"), pin(nil), pin("A"), pin("Unknown"), pin(nil), pin("B")]
        let ordered = ClipboardStore.pinnedByGroup(list, groups: ["A", "B"]).map { $0.group }
        #expect(ordered == [nil, nil, "A", "B", "B", "Unknown"])
    }

    @Test func sectionsSplitPinsIntoGroups() {
        func pin(_ group: String?) -> Clip { var c = Clip(kind: .text); c.text = "x"; c.pinned = true; c.group = group; return c }
        var recent = Clip(kind: .text); recent.text = "new"
        let sections = ClipSection.sections(of: [pin(nil), pin("Code"), recent], groups: ["Code", "Empty"])
        #expect(sections.map(\.title) == ["Pinned", "Code", "Past Hour"])
    }
}

/// Search reaches the whole text, and copies that differ only in spacing or tracking links count as one item.
@Suite struct SearchAndDuplicateTests {
    @Test func searchFindsTextPastTheTitle() {
        var long = Clip(kind: .text)
        long.text = String(repeating: "filler ", count: 60) + "the needle is here"
        #expect(long.title.count <= 160)
        #expect(ClipboardStore.matches(long, "needle"))
        #expect(ClipboardStore.matches(long, "NEEDLE"))
        #expect(!ClipboardStore.matches(long, "haystack"))
    }

    @Test func searchNeverLooksInsideSensitiveItems() {
        var secret = Clip(kind: .text)
        secret.text = "sk-live-hunter2"
        secret.sensitive = true
        #expect(!ClipboardStore.matches(secret, "hunter2"))
    }

    @Test func searchMatchesFileNames() {
        var file = Clip(kind: .file)
        file.paths = ["/Users/someone/Desktop/Invoice March.pdf", "/tmp/Brand colours.txt"]
        #expect(ClipboardStore.matches(file, "brand colours"))
    }

    @Test func sameContentIgnoresSpacingAndTracking() {
        #expect(Clip.contentKey("  hello\n") == Clip.contentKey("hello"))
        #expect(Clip.contentKey("hello world") != Clip.contentKey("hello  world"))
        #expect(Clip.contentKey("https://example.com/post?utm_source=x&id=4&fbclid=abc") == Clip.contentKey("https://example.com/post?id=4"))
        #expect(Clip.contentKey("https://Example.com/a/") == Clip.contentKey("https://example.com/a"))
        #expect(Clip.contentKey("https://example.com/a?id=4") != Clip.contentKey("https://example.com/a?id=5"))
        #expect(Clip.contentKey("https://open.spotify.com/track/1?si=xyz") == "https://open.spotify.com/track/1")
    }
}
