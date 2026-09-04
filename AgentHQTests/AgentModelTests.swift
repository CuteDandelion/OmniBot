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

    func testDisplayPathUsesTildeForHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(Agent.displayPath(home), "~")
        XCTAssertEqual(Agent.displayPath(home + "/Documents"), "~/Documents")
        XCTAssertEqual(Agent.displayPath("/tmp/workspace"), "/tmp/workspace")
    }

    func testRoleTitlesAndInstructions() {
        XCTAssertEqual(RolePreset.chiefOfStaff.defaultTitle, "Chief of Staff")
        XCTAssertTrue(RolePreset.chiefOfStaff.developerInstructions.contains("handoff"))
        XCTAssertTrue(RolePreset.softwareEngineer.developerInstructions.contains("Implement"))
        XCTAssertTrue(RolePreset.qaEngineer.developerInstructions.contains("tests"))
        XCTAssertEqual(RolePreset.custom.developerInstructions, "The user blurb is the role.")
    }

    func testResolvedDeveloperInstructions() throws {
        let engineer = try makeAgent(name: "Lin", role: .softwareEngineer, mascot: .cat)
        XCTAssertEqual(engineer.resolvedDeveloperInstructions, RolePreset.softwareEngineer.developerInstructions)

        let custom = try makeAgent(
            name: "Moth",
            role: .custom,
            mascot: .fox,
            customRoleTitle: "Researcher"
        )
        XCTAssertEqual(custom.resolvedDeveloperInstructions, "")
        custom.customInstructions = "  Review papers.  "
        XCTAssertEqual(custom.resolvedDeveloperInstructions, "Review papers.")
    }

    func testChiefOfStaffSeedEqualsPresetInstructions() throws {
        let seed = Agent.seededInstructions(for: .chiefOfStaff)
        XCTAssertEqual(seed, RolePreset.chiefOfStaff.developerInstructions)

        let agent = try makeAgent(
            name: "Ada",
            role: .chiefOfStaff,
            mascot: .bear,
            customInstructions: seed
        )
        XCTAssertEqual(agent.customInstructions, RolePreset.chiefOfStaff.developerInstructions)
        XCTAssertEqual(agent.resolvedDeveloperInstructions, RolePreset.chiefOfStaff.developerInstructions)
    }

    func testUserOverrideIsResolvedDeveloperInstructions() throws {
        let agent = try makeAgent(
            name: "Ada",
            role: .chiefOfStaff,
            mascot: .bear,
            customInstructions: RolePreset.chiefOfStaff.developerInstructions
        )
        agent.customInstructions = "  Coordinate only. Never write code.  "
        XCTAssertEqual(agent.resolvedDeveloperInstructions, "Coordinate only. Never write code.")
        XCTAssertNotEqual(agent.resolvedDeveloperInstructions, RolePreset.chiefOfStaff.developerInstructions)
    }

    func testSeededInstructionsUsesOverrideWhenPresent() {
        XCTAssertEqual(
            Agent.seededInstructions(for: .softwareEngineer, override: "  Ship it.  "),
            "Ship it."
        )
        XCTAssertEqual(
            Agent.seededInstructions(for: .qaEngineer, override: "   "),
            RolePreset.qaEngineer.developerInstructions
        )
        XCTAssertEqual(Agent.seededInstructions(for: .custom), "")
        XCTAssertEqual(Agent.seededInstructions(for: .custom, override: "  "), "")
        XCTAssertEqual(Agent.seededInstructions(for: .custom, override: "Be a critic."), "Be a critic.")
        XCTAssertNotEqual(Agent.seededInstructions(for: .custom), RolePreset.custom.developerInstructions)
    }

    func testStatusPipColors() {
        XCTAssertEqual(MascotState.idle.statusLabel, "idle")
        XCTAssertEqual(MascotState.working.statusLabel, "working")
        XCTAssertEqual(MascotState.waiting.statusLabel, "waiting")
        XCTAssertEqual(MascotState.needsApproval.statusLabel, "needs approval")
        XCTAssertEqual(MascotState.idle.pipColor, Tokens.muted)
        XCTAssertEqual(MascotState.working.pipColor, Tokens.accent)
        XCTAssertEqual(MascotState.waiting.pipColor, Tokens.attention)
        XCTAssertEqual(MascotState.needsApproval.pipColor, Tokens.danger)
    }

    private func makeAgent(
        name: String,
        role: RolePreset,
        mascot: MascotKind,
        customRoleTitle: String? = nil,
        customInstructions: String? = nil
    ) throws -> Agent {
        let schema = Schema([Agent.self, HandoffRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let agent = Agent(
            name: name,
            role: role,
            customRoleTitle: customRoleTitle,
            customInstructions: customInstructions,
            mascot: mascot,
            workspacePath: "/tmp"
        )
        context.insert(agent)
        return agent
    }
}
