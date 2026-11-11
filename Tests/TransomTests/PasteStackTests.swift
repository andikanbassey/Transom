import Foundation
import Testing
@testable import Transom

/// Paste Together and the paste stack decide what is pasted and in which order: both must be exact.
@Suite struct PasteJoiningTests {
    private func text(_ t: String, at seconds: TimeInterval, sensitive: Bool = false) -> Clip {
        var c = Clip(kind: .text); c.text = t; c.date = Date(timeIntervalSince1970: seconds); c.sensitive = sensitive; return c
    }

    @Test func copyOrderIsOldestFirst() {
        let picked = [text("b", at: 20), text("a", at: 10), text("c", at: 30)]
        #expect(Joining.ordered(picked, by: .copied).compactMap(\.text) == ["a", "b", "c"])
        #expect(Joining.ordered(picked, by: .picked).compactMap(\.text) == ["b", "a", "c"])
    }

    @Test func separators() {
        let items = [text("one", at: 1), text("two", at: 2)]
        #expect(Joining.text(items, separator: .newline) == "one\ntwo")
        #expect(Joining.text(items, separator: .blankLine) == "one\n\ntwo")
        #expect(Joining.text(items, separator: .comma) == "one, two")
        #expect(Joining.text(items, separator: .space) == "one two")
        #expect(Joining.text(items, separator: .tab) == "one\ttwo")
    }

    @Test func sensitiveAndPicturesAreLeftOut() {
        var picture = Clip(kind: .image); picture.imageFile = "x.png"
        let items = [text("keep", at: 1), text("hunter2", at: 2, sensitive: true), picture]
        #expect(Joining.text(items, separator: .newline) == "keep")
        #expect(Joining.text([picture], separator: .newline) == nil)
        // The stack pastes pictures one at a time, but never a sensitive item.
        #expect(PasteStack.queue(items, order: .copied).count == 2)
    }

    @Test func stackAdvancesToTheEnd() {
        #expect(PasteStack.next(after: 0, count: 3) == 1)
        #expect(PasteStack.next(after: 1, count: 3) == 2)
        #expect(PasteStack.next(after: 2, count: 3) == nil)
        #expect(PasteStack.next(after: 0, count: 1) == nil)
    }

    @Test func pickOrderKeepsClicksThenShownOrder() {
        let ids = (0..<5).map { _ in UUID() }
        // Clicked 3, 4 and 1 (4 later unpicked); then Select All added 0 and 2 in the order shown.
        let order = ClipboardStore.pickOrder(Set([ids[0], ids[1], ids[2], ids[3]]), recorded: [ids[3], ids[4], ids[1]], shown: ids)
        #expect(order == [ids[3], ids[1], ids[0], ids[2]])
    }
}
