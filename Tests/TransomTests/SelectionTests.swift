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
