import Foundation
import Testing
@testable import Transom

/// ⇧-arrow runs, auto-scroll at the edges of the drawer, and what a multi-item drag carries.
@Suite struct DrawerSelectTests {
    @Test func shiftRunKeepsWhatWasPickedBefore() {
        let ids = (0..<6).map { _ in UUID() }
        let base: Set<UUID> = [ids[5]]
        #expect(ClipboardStore.extended(base, anchor: ids[1], to: ids[3], in: ids) == Set([ids[1], ids[2], ids[3], ids[5]]))
        // Moving back past the start picks the other way.
        #expect(ClipboardStore.extended(base, anchor: ids[2], to: ids[0], in: ids) == Set([ids[0], ids[1], ids[2], ids[5]]))
        #expect(ClipboardStore.extended([], anchor: ids[2], to: ids[2], in: ids) == [ids[2]])
    }

    @Test func edgeDirection() {
        let v = CGRect(x: 100, y: 0, width: 600, height: 200)
        #expect(DragSelect.edgeDirection(pointer: CGPoint(x: 680, y: 50), viewport: v, horizontal: true) == 1)
        #expect(DragSelect.edgeDirection(pointer: CGPoint(x: 120, y: 50), viewport: v, horizontal: true) == -1)
        #expect(DragSelect.edgeDirection(pointer: CGPoint(x: 400, y: 50), viewport: v, horizontal: true) == 0)
        #expect(DragSelect.edgeDirection(pointer: CGPoint(x: 400, y: 190), viewport: v, horizontal: false) == 1)
        #expect(DragSelect.edgeDirection(pointer: CGPoint(x: 400, y: 50), viewport: .zero, horizontal: true) == 0)
    }

    @Test func sensitiveItemsAreNeverDraggedOut() {
        var secret = Clip(kind: .text); secret.text = "hunter2"; secret.sensitive = true
        var note = Clip(kind: .text); note.text = "hello"
        var files = Clip(kind: .file); files.paths = ["/tmp/a.txt", "/tmp/b.txt"]
        let writers = MultiDrag.writers(for: [secret, note, files])
        #expect(writers.count == 3)
        #expect((writers.first as? NSString) == "hello")
    }
}
