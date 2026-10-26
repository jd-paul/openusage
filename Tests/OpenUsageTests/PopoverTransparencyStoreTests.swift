import XCTest
@testable import OpenUsage

@MainActor
final class PopoverTransparencyStoreTests: XCTestCase {
    func testSecretCodeTogglesThePartyOnAndOff() {
        let store = PopoverTransparencyStore(reduceTransparency: false, increaseContrast: false)
        XCTAssertFalse(store.partyActive)

        store.toggleSecretCode()
        XCTAssertTrue(store.partyActive)

        store.toggleSecretCode()
        XCTAssertFalse(store.partyActive)
    }

    func testPartyYieldsToEitherAccessibilitySetting() {
        for store in [
            PopoverTransparencyStore(reduceTransparency: true, increaseContrast: false),
            PopoverTransparencyStore(reduceTransparency: false, increaseContrast: true)
        ] {
            store.toggleSecretCode()
            XCTAssertTrue(store.secretCodeActive)
            XCTAssertFalse(store.partyActive, "the egg never overrides Reduce Transparency or Increase Contrast")
        }
    }
}
