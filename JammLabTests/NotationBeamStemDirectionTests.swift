import XCTest
@testable import JammLab
final class NotationBeamStemDirectionTests: XCTestCase {
    func testNotesAboveMiddleLineUseDownStems() {
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [0, 1, 2]
            ),
            .down
        )
    }

    func testNotesBelowMiddleLineUseUpStems() {
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [6, 7, 8]
            ),
            .up
        )
    }

    func testSymmetricGroupUsesFirstNoteAsTieBreaker() {
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [1, 7]
            ),
            .down
        )
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [7, 1]
            ),
            .up
        )
    }

    func testAscendingAndDescendingGroupsUseWholeGroupExtremes() {
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [8, 6, 5]
            ),
            .up
        )
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [0, 2, 3]
            ),
            .down
        )
    }

    func testExplicitDirectionAndVoiceRolesHavePriority() {
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [8, 9],
                explicitDirections: [.down]
            ),
            .down
        )
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [0, 1],
                voiceRole: .upper
            ),
            .up
        )
        XCTAssertEqual(
            NotationBeamStemDirectionResolver.direction(
                staffPositions: [8, 9],
                voiceRole: .lower
            ),
            .down
        )
    }
}

