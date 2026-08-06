import XCTest
import AppKit
@testable import JustNote

/// Guards the code-block highlighting contract JustNote's live editor depends on.
/// `CodeBlockSyntaxHighlighter` is the highlighter actually injected into the
/// editor: it must supply a visible background fill, emit per-token colors for
/// language-tagged fences, and — crucially — NOT auto-detect a language for a
/// bare fence (which colors plain prose as if it were source). Because the
/// visual result can't be screenshotted in CI, these are the regression signals
/// if the pinned dependency or the wrapper's gating ever change.
final class SyntaxHighlighterIntegrationTests: XCTestCase {

    func testBackgroundColorIsOpaqueVisibleTint() {
        // The default PlainTextSyntaxHighlighter returns alpha 0 (invisible);
        // the whole point of the swap is an actually-visible fill.
        XCTAssertGreaterThan(CodeBlockSyntaxHighlighter().backgroundColor().alphaComponent, 0.5)
    }

    func testTaggedFenceEmitsTokenColors() throws {
        let highlighter = CodeBlockSyntaxHighlighter()
        for (language, code) in [
            ("swift", "let greeting = \"hello\"\nfunc main() { print(greeting) }"),
            ("python", "def main():\n    x = 1\n    return x")
        ] {
            let highlighted = try XCTUnwrap(
                highlighter.highlight(code: code, language: language),
                "expected highlighted output for \(language)"
            )
            XCTAssertTrue(
                hasMultipleForegroundColors(highlighted),
                "expected multiple token colors for \(language)"
            )
        }
    }

    func testBareFenceIsNotAutoDetected() {
        let highlighter = CodeBlockSyntaxHighlighter()
        let prose = "just some prose in a fence, not code at all"
        // No language hint → no highlighting, so prose isn't miscolored as source.
        XCTAssertNil(highlighter.highlight(code: prose, language: nil))
        XCTAssertNil(highlighter.highlight(code: prose, language: ""))
        XCTAssertNil(highlighter.highlight(code: prose, language: "   "))
    }

    private func hasMultipleForegroundColors(_ string: NSAttributedString) -> Bool {
        var colors: Set<String> = []
        string.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: string.length)
        ) { value, _, _ in
            if let color = value as? NSColor {
                colors.insert(color.description)
            }
        }
        return colors.count > 1
    }
}
