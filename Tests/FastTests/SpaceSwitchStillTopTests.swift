import Foundation
import Testing
@testable import Fast

/// A change of space holds the top of the column still, as Arc's does: the
/// address and the pinned extensions' row stay where they are whatever the
/// next space has in front, a site, a blank tab or nothing, so only the
/// space's own part slides, and the pins every space shares stand still
/// over it (SpacePager.hold).
@MainActor
@Suite(.serialized)
struct SpaceSwitchStillTopTests {
    @MainActor private final class World {
        let id = UUID()
        let browser: Browser
        private var lists: [URL] = []
        private let spaces: Any?
        private let addressBar: Bool
        private let spacesList: Data?
        private static var spacesFile: URL { Store.file("spaces.json") }

        init() {
            spaces = Store.settings.object(forKey: "spaces")
            spacesList = try? Data(contentsOf: World.spacesFile)
            browser = Browser(windowID: id)
            browser.prefs.usesSpaces = true
            // The address in the column, not over the page.
            addressBar = browser.prefs.addressBar
            browser.prefs.addressBar = false
        }

        /// A space with sign-ins of its own and five extensions pinned in
        /// its list, never loaded: read as the column reads a parked one's.
        func space(_ name: String) throws -> Space {
            let space = Space(id: UUID(), name: name, icon: "🧪", ownSignIns: true)
            let list = Extensions.list(of: space.id)
            try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
            let pinned = (0..<5).map { index in
                Installed(id: String(repeating: String(UnicodeScalar(UInt8(97 + index))), count: 32), name: "Pinned \(index)",
                          version: "1", enabled: true, fromStore: true, permissions: [], pinned: true)
            }
            try JSONEncoder().encode(pinned).write(to: list)
            lists.append(list)
            return space
        }

        func site() -> Tab {
            let tab = Tab()
            tab.restore(url: URL(string: "https://example.test/")!, title: "Example")
            browser.prepare(tab)
            return tab
        }

        func close() {
            browser.prefs.addressBar = addressBar
            browser.letGo()
            lists.forEach { try? FileManager.default.removeItem(at: $0) }
            Store.settings.set(spaces, forKey: "spaces")
            if let spacesList { try? spacesList.write(to: World.spacesFile, options: .atomic) } else { try? FileManager.default.removeItem(at: World.spacesFile) }
            try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            for space in browser.spaces {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString)-\(space.id.uuidString).json"))
            }
            Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
        }
    }

    /// On main a blank tab, or none, dropped the row: every pin under it
    /// went up a row on a new tab, and on a change of space to or from one.
    @Test func theExtensionsRowStaysOnABlankTabOrNone() throws {
        let world = World()
        defer { world.close() }
        let space = try world.space("Here")
        let shown = SidePlate.extensionPlate(in: world.browser, space: space.id, tab: world.site())
        #expect(shown.extensionHeight > 0)
        let blank = Tab()
        #expect(blank.isBlank)
        #expect(SidePlate.extensionPlate(in: world.browser, space: space.id, tab: blank) == shown)
        #expect(SidePlate.extensionPlate(in: world.browser, space: space.id, tab: nil) == shown)
    }

    /// The user's case: a site in front here, nothing in the space beside
    /// it. On main the plates differed, so the row was pictured with the
    /// address and the pins in its pages and they slid with it; the same
    /// plate keeps them in the still head, the live row under them.
    @Test func theAddressAndPinsStayOutOfTheRowToASpaceWithNoTab() throws {
        let world = World()
        defer { world.close() }
        let browser = world.browser
        let here = try world.space("Here"), empty = try world.space("Empty")
        browser.spaces = [here, empty]
        browser.spaceID = here.id
        let site = world.site()
        browser.lay([site])
        browser.select(site)
        browser.parked[empty.id] = Parked(tabs: [], active: nil)
        #expect(browser.active === site)
        #expect(browser.sidePlated)
        #expect(SidePlate.extensionPlate(in: browser, space: here.id, tab: browser.active, shown: browser.sidePlated).extensionHeight > 0)
        #expect(SpacePager.movesPlate(browser, toward: 1) == false)
        #expect(SpacePager.movesPlate(browser, toward: nil) == false)
    }
}
