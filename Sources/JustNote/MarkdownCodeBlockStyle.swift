import MarkdownView
import SwiftUI

func normalizedCodeBlockContent(_ content: String) -> String {
    guard content.last == "\n" else { return content }
    return String(content.dropLast())
}

struct NormalizedCodeBlockStyle: MarkdownCodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        var normalizedConfiguration = configuration
        normalizedConfiguration.code = normalizedCodeBlockContent(normalizedConfiguration.code)
        return DefaultCodeBlockStyle().makeBody(configuration: normalizedConfiguration)
    }
}
