import SwiftData
import XCTest
@testable import AgentHQ

final class AgentModelTests: XCTestCase {
    func testChiefOfStaffDefaultMascotIsBear() {
        XCTAssertEqual(RolePreset.chiefOfStaff.defaultMascot, .bear)
    }

    func testRoleDefaultMascots() {
        XCTAssertEqual(RolePreset.softwareEngineer.defaultMascot, .cat)
        XCTAssertEqual(RolePreset.qaEngineer.defaultMascot, .owl)
        XCTAssertEqual(RolePreset.custom.defaultMascot, .fox)
    }

    func testChiefOfStaffCanUseCorgiMascot() throws {
        let agent = try makeAgent(name: "Ada", role: .chiefOfStaff, mascot: .corgi)
        XCTAssertEqual(agent.role, .chiefOfStaff)
        XCTAssertEqual(agent.role.defaultMascot, .bear)
        XCTAssertEqual(agent.mascot, .corgi)
        XCTAssertNotEqual(agent.mascot, agent.role.defaultMascot)
    }

    func testDisplayRoleUsesPresetTitle() throws {
        let agent = try makeAgent(name: "Lin", role: .softwareEngineer, mascot: .cat)
        XCTAssertEqual(agent.displayRole, "Software Engineer")
    }

    func testDisplayRoleUsesCustomTitle() throws {
        let agent = try makeAgent(
            name: "Moth",
            role: .custom,
            mascot: .fox,
            customRoleTitle: "Researcher"
        )
        XCTAssertEqual(agent.displayRole, "Researcher")
    }

    func testDisplayRoleFallsBackWhenCustomTitleMissing() throws {
        let agent = try makeAgent(name: "Moth", role: .custom, mascot: .rabbit)
        XCTAssertEqual(agent.displayRole, "Custom")
    }

    func testRoleTitlesAndInstructions() {
        XCTAssertEqual(RolePreset.chiefOfStaff.defaultTitle, "Chief of Staff")
        XCTAssertTrue(RolePreset.chiefOfStaff.developerInstructions.contains("handoff"))
        XCTAssertTrue(RolePreset.softwareEngineer.developerInstructions.contains("Implement"))
        XCTAssertTrue(RolePreset.qaEngineer.developerInstructions.contains("tests"))
        XCTAssertEqual(RolePreset.custom.developerInstructions, "The user blurb is the role.")
    }

    private func makeAgent(
        name: String,
        role: RolePreset,
        mascot: MascotKind,
        customRoleTitle: String? = nil
    ) throws -> Agent {
        let schema = Schema([Agent.self, HandoffRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let agent = Agent(
            name: name,
            role: role,
            customRoleTitle: customRoleTitle,
            mascot: mascot,
            workspacePath: "/tmp"
        )
        context.insert(agent)
        return agent
    }
}
