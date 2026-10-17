import XCTest
@testable import JustNote

final class EditorBottomSpaceTests: XCTestCase {
    func testEmptyAndShortContentFillViewport() {
        for height: CGFloat in [0, 20, 59, 100] {
            XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: height, viewportHeight: 400, lineHeight: 16), 400)
        }
    }

    func testSpaceRampsBeforeContentFillsViewport() {
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 300, viewportHeight: 400, lineHeight: 16), 500)
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 400, viewportHeight: 400, lineHeight: 16), 584)
    }

    func testLongContentGetsHalfViewportMinusOneLine() {
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 2000, viewportHeight: 400, lineHeight: 16), 2184)
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 2000, viewportHeight: 1200, lineHeight: 16), 2584)
    }

    func testTinyViewportProducesFiniteNonnegativeExtent() {
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 20, viewportHeight: 0, lineHeight: 16), 20)
        XCTAssertEqual(EditorBottomSpace.documentHeight(contentHeight: 20, viewportHeight: 10, lineHeight: 16), 20)
    }
}
