import XCTest
import AppKit
import MarkdownEngineCodeBlocks

/// Guards the code-block highlighting contract JustNote's `LiveMarkdownEditor`
/// now depends on: the injected `HighlighterSwiftBridge` (constructed with the
/// same defaults JustNote uses) must supply a visible background fill and emit
/// per-token foreground colors. Because HighlighterSwift is pinned exactly and
/// the visual result can't be screenshotted in CI, this test is the regression
/// signal if a future dependency bump silently breaks either behavior.
final class SyntaxHighlighterIntegrationTests: XCTestCase {

    func testBackgroundColorIsOpaqueVisibleTint() {
        let highlighter = HighlighterSwiftBridge()
        // The default PlainTextSyntaxHighlighter returns alpha 0 (invisible);
        // the whole point of the swap is an actually-visible fill.
        XCTAssertGreaterThan(highlighter.backgroundColor().alphaComponent, 0.5)
    }

    func testHighlightEmitsTokenColorsForKnownLanguages() throws {
        let highlighter = HighlighterSwiftBridge()
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

    func testNoLanguageFenceDoesNotCrash() {
        let highlighter = HighlighterSwiftBridge()
        // Auto-detect path (no language). Result may be nil; must not throw/crash.
        _ = highlighter.highlight(code: "plain text with no language", language: nil)
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
