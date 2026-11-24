import AppKit
import Testing
@testable import Fast

/// #819: the bench takes the first window at launch. Closed while a second
/// is up, that window is kept out of sight with its tabs, and an agent's
/// `tabs` listed those, one of them "in front", instead of the second's.
@MainActor @Suite(.serialized)
struct AgentLiveWindowTests {
    /// A first window with a tab on a.example, a second in front on
    /// b.example, and the first closed.
    private func closingTheFirst(_ body: (_ first: Browser, _ second: Browser, _ stale: Tab) throws -> Void) throws {
        try #require(Store.testing && Store.unitTests && Store.settings !== UserDefaults.standard)
        func window() -> NSWindow {
            let made = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 800, height: 600),
                                styleMask: .borderless, backing: .buffered, defer: false)
            made.isReleasedWhenClosed = false
            return made
        }
        func tab(_ url: String, in browser: Browser) -> Tab {
            let tab = Tab()
            tab.restore(url: URL(string: url)!, title: url)
            browser.lay(browser.tabs + [tab])
            browser.activeID = tab.id
            return tab
        }
        let first = Browser()
        let firstWindow = window()
        BrowserWindows.shared.register(firstWindow, for: first)
        firstWindow.orderFront(nil)
        let stale = tab("https://a.example.test/", in: first)

        let second = Browser(windowID: UUID())
        let secondWindow = window()
        BrowserWindows.shared.register(secondWindow, for: second)
        secondWindow.orderFront(nil)
        _ = tab("https://b.example.test/download", in: second)
        defer {
            for (browser, window) in [(first, firstWindow), (second, secondWindow)] {
                browser.tabs.forEach { $0.close() }
                window.close()
                BrowserWindows.shared.forgetForTests(browser)
                browser.letGo()
            }
            if let id = second.windowID {
                Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            }
        }

        #expect(BrowserWindows.shared.live(first) === first)
        firstWindow.close()
        try body(first, second, stale)
    }

    @Test func aClosedFirstWindowHandsTheToolsToTheOneInFront() throws {
        try closingTheFirst { first, second, _ in
            let live = BrowserWindows.shared.live(first)
            #expect(live === second)

            var said: [String: Any] = [:]
            Bench().handleAgentTabs(AgentCall(bench: Bench(), verb: "agent-tabs", request: [:], browser: live) { said = $0 })
            let rows = try #require(said["tabs"] as? [[String: Any]])
            let front = rows.filter { $0["active"] as? Bool == true }.compactMap { $0["url"] as? String }
            #expect(front == ["https://b.example.test/download"])
            #expect(!rows.contains { $0["url"] as? String == "https://a.example.test/" })
        }
    }

    /// A task at work in the first window when it closed still reaches its
    /// tab, and what it does there is done in that window, not the one in front.
    @Test func aTabInTheClosedFirstWindowIsWorkedInItsOwnWindow() throws {
        try closingTheFirst { first, second, stale in
            let request: [String: Any] = ["id": Bench.short(stale)]
            let front = second.activeID
            let browser = Bench().holder(of: request, in: BrowserWindows.shared.live(first))
            #expect(browser === first)
            let tab = try #require(Bench().find(request, in: browser))
            #expect(tab === stale)
            // As the select verb does with the tab it found.
            browser.select(tab)
            #expect(second.activeID == front)
        }
    }
}
