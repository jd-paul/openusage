import XCTest
@testable import OpenUsage

/// What a user pastes into the sign-in sheet: a bare code, a `code#state` pair, or the whole callback
/// URL the browser landed on. Only the URL is read for its query; the other two are not relative URLs.
final class AuthorizationCodeParsingTests: XCTestCase {
    func testAPastedCodeWithItsStateIsAccepted() throws {
        XCTAssertEqual(try authorizationCode(from: .pasted("abc123#expected"), expectedState: "expected", requireState: true), "abc123")
        XCTAssertEqual(try authorizationCode(from: .pasted("  abc123#expected\n"), expectedState: "expected", requireState: true), "abc123")
    }

    func testAPastedCodeWithTheWrongOrAMissingStateIsRefused() {
        XCTAssertThrowsError(try authorizationCode(from: .pasted("abc123#other"), expectedState: "expected", requireState: true)) {
            XCTAssertEqual($0.localizedDescription, LoginError.invalidState.localizedDescription)
        }
        XCTAssertThrowsError(try authorizationCode(from: .pasted("abc123"), expectedState: "expected", requireState: true)) {
            XCTAssertEqual($0.localizedDescription, LoginError.invalidState.localizedDescription)
        }
    }

    func testABareCodeIsAcceptedWhereNoStateIsRequired() throws {
        XCTAssertEqual(try authorizationCode(from: .pasted("abc123"), expectedState: "expected", requireState: false), "abc123")
        XCTAssertThrowsError(try authorizationCode(from: .pasted("   "), expectedState: "expected", requireState: false)) {
            XCTAssertEqual($0.localizedDescription, LoginError.invalidCode.localizedDescription)
        }
    }

    func testAWholeCallbackURLIsReadForItsCodeAndState() throws {
        let callback = "http://127.0.0.1:1455/auth/callback?code=abc123&state=expected"
        XCTAssertEqual(try authorizationCode(from: .pasted(callback), expectedState: "expected", requireState: true), "abc123")
        XCTAssertThrowsError(try authorizationCode(from: .pasted("http://127.0.0.1:1455/auth/callback?code=abc123&state=other"), expectedState: "expected", requireState: true)) {
            XCTAssertEqual($0.localizedDescription, LoginError.invalidState.localizedDescription)
        }
        XCTAssertThrowsError(try authorizationCode(from: .pasted("http://127.0.0.1:1455/auth/callback"), expectedState: "expected", requireState: false)) {
            XCTAssertEqual($0.localizedDescription, LoginError.invalidCode.localizedDescription)
        }
    }
}
