// Pr0gramm/Pr0gramm/Features/Views/CommentView.swift
// --- START OF COMPLETE FILE ---

import SwiftUI
import Foundation

struct CommentView: View {
    let comment: ItemComment
    @Binding var previewLinkTarget: PreviewLinkTarget? // <-- GEÄNDERT: Typ ist jetzt Wrapper

    private var markEnum: Mark { Mark(rawValue: comment.mark) }
    private var userMarkColor: Color { markEnum.displayColor }
    private var userMarkName: String { markEnum.displayName }
    private var score: Int { comment.up - comment.down }

    private var relativeTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(comment.created))
        let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var attributedCommentContent: AttributedString {
        var attributedString = AttributedString(comment.content)
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: comment.content, options: [], range: NSRange(location: 0, length: comment.content.utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: attributedString), let url = match.url else { continue }
                attributedString[range].link = url
                attributedString[range].foregroundColor = .accentColor
            }
        } catch { print("Error creating NSDataDetector: \(error)") }
        return attributedString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(userMarkColor).overlay(Circle().stroke(Color.black, lineWidth: 0.5)).frame(width: 8, height: 8)
                Text(comment.name).font(.caption.weight(.semibold))
                Text("•").foregroundColor(.secondary)
                Text("\(score)").font(.caption).foregroundColor(score > 0 ? .green : (score < 0 ? .red : .secondary))
                Text("•").foregroundColor(.secondary)
                Text(relativeTime).font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            Text(attributedCommentContent)
                .font(.footnote)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 6)
        .environment(\.openURL, OpenURLAction { url in
            if let itemID = parsePr0grammLink(url: url) {
                print("Pr0gramm link tapped, attempting to preview item ID: \(itemID)")
                // --- GEÄNDERT: Setze State mit Wrapper Struct ---
                self.previewLinkTarget = PreviewLinkTarget(id: itemID)
                return .handled
            } else {
                print("Non-pr0gramm link tapped: \(url). Opening in system browser.")
                return .systemAction
            }
        })
    }

    private func parsePr0grammLink(url: URL) -> Int? {
        guard let host = url.host?.lowercased(),
              (host == "pr0gramm.com" || host == "www.pr0gramm.com") else {
            return nil
        }
        let pathComponents = url.pathComponents
        for component in pathComponents.reversed() {
            if let itemID = Int(component) {
                return itemID
            }
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "id", let value = item.value, let itemID = Int(value) {
                    return itemID
                }
            }
        }
        print("Could not parse item ID from pr0gramm link: \(url)")
        return nil
    }
}

// Preview für CommentView (State Typ geändert)
#Preview {
    // GEÄNDERT: State Typ für Preview
    @State var previewTarget: PreviewLinkTarget? = nil
    let sampleComment = ItemComment(id: 1, parent: 0, content: "Das ist ein Beispielkommentar mit einem Link: https://pr0gramm.com/top/6595750 und noch mehr Text sowie google.de", created: Int(Date().timeIntervalSince1970) - 120, up: 15, down: 2, confidence: 0.9, name: "TestUser", mark: 1)

    return CommentView(comment: sampleComment, previewLinkTarget: $previewTarget)
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
}
// --- END OF COMPLETE FILE ---
