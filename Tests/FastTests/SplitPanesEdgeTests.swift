import AppKit
import Foundation
import Testing
@testable import Fast

/// Three or four panes at their edges: a divider pushing those before it, the
/// window and column keeping every pane its width, a third chip under the
/// pointer, a split parked in a space sliding in, and what floats over the
/// pane in front.
@MainActor @Suite(.serialized)
struct SplitPanesEdgeTests {
    private func window(_ count: Int) -> (Browser, UUID, [Tab]) {
        _ = NSApplication.shared
        let id = UUID()
        let browser = Browser(windowID: id)
        browser.splitBook.place = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let tabs = (0..<count).map { browser.open(URL(string: "https://example.test/\($0)")!, foreground: $0 == 0) }
        browser.lay(tabs)
        return (browser, id, tabs)
    }

    private func forget(_ id: UUID) {
        try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
    }

    private func show(_ browser: Browser, _ pair: Pair, front: Tab) async throws {
        browser.pairs.append(pair)
        browser.select(front)
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(30))
            browser.settleNow()
        }
    }

    @Test func aLaterDividerPushesTheOnesBeforeIt() async throws {
        let (browser, id, tabs) = window(3)
        defer { forget(id) }
        try await show(browser, Pair(first: tabs[0].id, second: tabs[1].id, share: 1.0 / 3, more: [tabs[2].id], cuts: [2.0 / 3]), front: tabs[0])
        browser.splitDrag.armed = true
        browser.splitDrag.grabbedCuts = [1.0 / 3, 2.0 / 3]
        // The second divider taken far left: the first goes back before it.
        browser.dragCuts(to: [1.0 / 3, 0.2])
        let cuts = try #require(browser.splitDrag.cuts)
        let panes = SplitLayout.panes(3, .across, cuts: cuts, in: browser.splitBook.place).panes
        #expect(cuts[0] < 0.3 && cuts[1] < 0.5)
        #expect(panes.allSatisfy { $0.width >= Pair.narrowest })
        // The first taken right still pushes the second on, as before.
        browser.dragCuts(to: [0.9, 2.0 / 3])
        let on = try #require(browser.splitDrag.cuts)
        #expect(on[1] > 2.0 / 3 && SplitLayout.panes(3, .across, cuts: on, in: browser.splitBook.place).panes.allSatisfy { $0.width >= Pair.narrowest })
    }

    @Test func theColumnLeavesEveryPaneItsWidth() async throws {
        let (browser, id, tabs) = window(3)
        defer { forget(id) }
        try await show(browser, Pair(first: tabs[0].id, second: tabs[1].id, more: [tabs[2].id]), front: tabs[0])
        let three = 3 * Pair.narrowest + 2 * Pair.gap
        #expect(browser.columnMost == browser.splitBook.place.width + browser.sideShown - three)
        // Two side by side: as before.
        browser.leaveSplit(tabs[2].id)
        #expect(browser.stagePair?.halves == true)
        #expect(browser.columnMost == browser.splitBook.place.width + browser.sideShown - Pair.room)
    }

    @Test func aThirdChipIsTheTabUnderThePointer() {
        let (browser, id, tabs) = window(4)
        defer { forget(id); browser.letGo() }
        browser.pairs.append(Pair(first: tabs[0].id, second: tabs[1].id, more: [tabs[2].id]))
        let cell = ColumnCell(kind: .pair)
        cell.frame = CGRect(x: 0, y: 0, width: 240, height: 34)
        cell.bind(ColumnItem(id: tabs[0].id.uuidString, kind: .pair(tabs[0], tabs[1]), indent: 0, y: 0, height: 34),
                  .init(browser: browser, look: .init(tone: nil, scheme: .light, titleSize: 13, grain: 0), liveID: nil), force: true)
        #expect(cell.tabUnderPointer(hovered: tabs[2]) == tabs[2].id)
        #expect(cell.tabUnderPointer(hovered: tabs[1]) == tabs[1].id)
        // A tab of no split, or of another row: nothing.
        #expect(cell.tabUnderPointer(hovered: tabs[3]) == nil)
    }

    @Test func aParkedSplitKeepsItsPanes() {
        let (browser, id, _) = window(1)
        defer { forget(id) }
        let away = (0..<3).map { _ in Tab() }
        browser.parked[UUID()] = Parked(tabs: away, active: away[0].id,
                                        pairs: [Pair(first: away[0].id, second: away[1].id, more: [away[2].id])])
        #expect(browser.morePanes(of: away[0].id).map(\.id) == [away[2].id])
        #expect(browser.morePanes(of: away[1].id).isEmpty)
    }

    @Test func whatFloatsOverThePageStaysOverThePaneInFront() async throws {
        let (browser, id, tabs) = window(4)
        defer { forget(id) }
        try await show(browser, Pair(first: tabs[0].id, second: tabs[1].id, more: [tabs[2].id, tabs[3].id], arrangement: .grid, cuts: [0.5]), front: tabs[3])
        let room = browser.splitBook.place
        let grid = SplitLayout.panes(4, .grid, cuts: [0.5, 0.5], in: room).panes
        // Bottom right: down by the top row and the gap, nothing to its right.
        let inset = try #require(browser.frontPaneInset())
        #expect(inset.top == grid[3].minY - room.minY && inset.top > 0)
        #expect(inset.bottom == 0 && inset.trailing == 0)
        browser.focus(tabs[0])
        let topLeft = try #require(browser.frontPaneInset())
        #expect(topLeft.top == 0 && topLeft.bottom == room.maxY - grid[0].maxY && topLeft.trailing == room.maxX - grid[0].maxX)
        // Two halves keep their own way (frontTrail).
        browser.removePane(tabs[3].id, from: try #require(browser.stagePair))
        browser.removePane(tabs[2].id, from: try #require(browser.stagePair))
        #expect(browser.stagePair?.halves == true && browser.frontPaneInset() == nil)
    }
}
