import Foundation

extension String {
    /// ClanGen's inline `<i>`, `<b>` and `<br>` tags as styled text.
    var storyText: AttributedString {
        let markdown = self
            .replacing("<i/>", with: "")
            .replacing("<i>", with: "_").replacing("</i>", with: "_")
            .replacing("<b>", with: "**").replacing("</b>", with: "**")
            .replacing("<br>", with: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(self)
    }
}
