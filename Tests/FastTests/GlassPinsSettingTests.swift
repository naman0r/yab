import AppKit
import Testing
@testable import Fast

/// Settings › Appearance › Glass pins: on unless turned off, the same switch
/// for the Settings row, the yab command and agents, and yours on every Mac.
@MainActor @Suite(.serialized)
struct GlassPinsSettingTests {
    @Test func glassPinsAreOnUntilTurnedOffAndTheSameSwitchEverywhere() throws {
        let key = "pins.glass"
        let previous = Store.settings.object(forKey: key)
        defer { Store.settings.set(previous, forKey: key) }
        Store.settings.removeObject(forKey: key)

        let prefs = Preferences()
        #expect(prefs.glassPins)
        let item = try #require(SettingsItem.all.first { $0.id == "glass-pins" })
        #expect(item.page == .appearance)
        #expect(NativeActions.classification(item) == "read_write")
        let setting = try #require(NativeSetting.all.first { $0.id == item.id })
        #expect(setting.read(prefs) == .bool(true))

        try setting.write(prefs, .bool(false))
        #expect(!prefs.glassPins)
        #expect(Store.settings.object(forKey: key) as? Bool == false)
        #expect(setting.saved == .bool(false))
        #expect(!Preferences().glassPins)

        try setting.write(prefs, .bool(true))
        #expect(prefs.glassPins && setting.saved == .bool(true))
        #expect(SyncShapes.settingKeys.contains(key))
    }
}
