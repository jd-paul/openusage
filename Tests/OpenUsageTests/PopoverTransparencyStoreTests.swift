import XCTest
@testable import OpenUsage

@MainActor
final class PopoverTransparencyStoreTests: XCTestCase {
    /// Isolated, throwaway defaults per test (pattern from `RefreshSettingTests`).
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "OpenUsageTests.Transparency.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// A store on throwaway defaults with the accessibility flags pinned (both off by default), so the
    /// egg's resolved style is deterministic regardless of the test host's real accessibility settings.
    private func makeStore(_ name: String,
                           reduceTransparency: Bool = false,
                           increaseContrast: Bool = false) -> PopoverTransparencyStore {
        PopoverTransparencyStore(defaults: makeDefaults(name),
                                 reduceTransparency: reduceTransparency,
                                 increaseContrast: increaseContrast)
    }

    func testIncreaseTransparencyDefaultsOffAndPersistsBothTransitions() {
        let defaults = makeDefaults("persist")
        let store = PopoverTransparencyStore(defaults: defaults)
        XCTAssertFalse(store.increaseTransparency)

        store.increaseTransparency = true
        XCTAssertTrue(PopoverTransparencyStore(defaults: defaults).increaseTransparency)

        store.increaseTransparency = false
        XCTAssertFalse(PopoverTransparencyStore(defaults: defaults).increaseTransparency)
    }

    func testEggStateIsNeverPersisted() {
        let defaults = makeDefaults("ephemeral")
        let store = PopoverTransparencyStore(defaults: defaults)
        store.toggleSecretCode()
        store.drunkMode = true
        XCTAssertTrue(store.secretCodeActive)
        // The egg is ephemeral: a fresh store (a relaunch) starts clean.
        let reloaded = PopoverTransparencyStore(defaults: defaults)
        XCTAssertFalse(reloaded.secretCodeActive)
        XCTAssertFalse(reloaded.drunkMode)
    }

    func testTurningEggOffClearsDrunkMode() {
        let store = makeStore("drunk")
        store.toggleSecretCode()        // on
        store.drunkMode = true
        store.toggleSecretCode()        // off
        XCTAssertFalse(store.secretCodeActive)
        XCTAssertFalse(store.drunkMode, "Drunk Mode clears when the egg turns off")
    }

    // MARK: - Egg state machine (Normal 1, Increase Transparency 2, Party 3, Drunk 4)

    func testPartyModeReturnsToEitherPriorBaseStyle() {
        for increased in [false, true] {
            let store = makeStore(increased ? "partyIncreased" : "partyOpaque")
            store.increaseTransparency = increased
            XCTAssertFalse(store.secretCodeActive)

            store.toggleSecretCode()
            XCTAssertTrue(store.secretCodeActive)
            XCTAssertEqual(store.effectiveStyle, .party)

            store.toggleSecretCode()
            XCTAssertFalse(store.secretCodeActive)
            XCTAssertEqual(store.increaseTransparency, increased)
            XCTAssertEqual(store.effectiveStyle, increased ? .increased : .opaque)
        }
    }

    func testPartyToggleOffFromState4ClearsDrunkAndReturnsToBase() {
        // 1 -> 3 -> 4, then the egg off goes 4 -> base (NOT 4 -> 3), clearing Drunk along the way.
        let store = makeStore("p4base1")
        store.toggleSecretCode()                    // 1 -> 3
        store.drunkMode = true                       // 3 -> 4
        XCTAssertEqual(store.effectiveStyle, .drunk)
        store.toggleSecretCode()                    // 4 -> base
        XCTAssertFalse(store.secretCodeActive)
        XCTAssertFalse(store.drunkMode, "can't be drunk without the party")
        XCTAssertEqual(store.effectiveStyle, .opaque)
    }

    func testDrunkToggleOffStaysInPartyState3() {
        // The only way 4 -> 3 is turning Drunk off; the egg stays active.
        let store = makeStore("d4to3")
        store.toggleSecretCode()                    // 1 -> 3
        store.drunkMode = true                       // 3 -> 4
        store.drunkMode = false                      // 4 -> 3
        XCTAssertTrue(store.secretCodeActive, "still in the party")
        XCTAssertEqual(store.effectiveStyle, .party)
    }

    func testBaseStateIsRememberedAcrossTheEgg() {
        // Older state memory: Increase Transparency (base 2) survives the whole 2 -> 3 -> 4 -> 2 round
        // trip untouched, because its Settings toggle is frozen while the egg runs. (Asserts the stored
        // base, not effectiveStyle.)
        let store = makeStore("remember")
        store.increaseTransparency = true            // base 2
        store.toggleSecretCode()                     // 2 -> 3
        store.drunkMode = true                        // 3 -> 4
        store.toggleSecretCode()                     // 4 -> base
        XCTAssertFalse(store.secretCodeActive)
        XCTAssertTrue(store.increaseTransparency, "the prior base (Increase Transparency) is restored")
    }

    func testEffectiveStyleFollowsEgg() {
        // With the accessibility flags pinned off, the egg resolves to the readable party / drunk.
        let store = makeStore("style")
        store.toggleSecretCode()        // secret code -> readable party
        XCTAssertEqual(store.effectiveStyle, .party)
        XCTAssertEqual(store.surfaceTreatment, .translucent)
        store.drunkMode = true          // Drunk Mode -> woozy, barely-readable drunk
        XCTAssertEqual(store.effectiveStyle, .drunk)
        store.toggleSecretCode()        // off; proper toggle is off too -> opaque
        XCTAssertEqual(store.effectiveStyle, .opaque)
        XCTAssertEqual(store.surfaceTreatment, .opaque)
    }

    // MARK: - Accessibility clamp (the egg yields to Reduce Transparency / Increase Contrast)

    func testEggYieldsToEitherAccessibilitySetting() {
        for store in [
            makeStore("eggA11yReduce", reduceTransparency: true),
            makeStore("eggA11yContrast", increaseContrast: true)
        ] {
            store.toggleSecretCode()
            XCTAssertTrue(store.secretCodeActive)
            XCTAssertEqual(store.effectiveStyle, .opaque)
            XCTAssertEqual(store.surfaceTreatment, .opaque)

            store.drunkMode = true
            XCTAssertEqual(store.effectiveStyle, .opaque)
        }
    }

    func testPopoverShownIsNeverPersisted() {
        // popoverShown is runtime-transient like the egg: a fresh store (a relaunch) starts hidden.
        let defaults = makeDefaults("shownEphemeral")
        let store = PopoverTransparencyStore(defaults: defaults)
        store.setPopoverShown(true)
        XCTAssertTrue(store.popoverShown)
        XCTAssertFalse(PopoverTransparencyStore(defaults: defaults).popoverShown, "not persisted")
    }
}
