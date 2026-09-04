import XCTest
@testable import AgentHQ

final class AgentHQScaffoldTests: XCTestCase {
    func testCardRadiusMatchesPrimer() {
        XCTAssertEqual(Tokens.cardRadius, 6)
    }
}
