import Foundation

/// Adds links to plain API text without changing the text sent to the server.
enum MessageTextFormatter {
    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    // pr0.app uses /\B@([a-z0-9]{2,32})/gi. Spell out JavaScript's ASCII
    // word boundary: Foundation's \B uses different Unicode semantics.
    // Partial matches (e.g. @foo in @foo_bar) intentionally match the website.
    private static let mentionRegex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])@([A-Za-z0-9]{2,32})"#
    )

    static func attributedString(for text: String) -> AttributedString {
        var result = AttributedString(text)
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let links = linkDetector.matches(in: text, range: fullRange)

        for link in links {
            guard let range = Range(link.range, in: result), let url = link.url else { continue }
            result[range].link = url
        }

        for mention in mentionRegex.matches(in: text, range: fullRange) {
            // Preserve complete URL/mailto links, including any @ in their text.
            guard !links.contains(where: { NSIntersectionRange($0.range, mention.range).length > 0 }),
                  let range = Range(mention.range, in: result),
                  let nameRange = Range(mention.range(at: 1), in: text),
                  let url = URL(string: "https://pr0.app/user/\(text[nameRange])") else { continue }
            result[range].link = url
        }

        return result
    }
}
