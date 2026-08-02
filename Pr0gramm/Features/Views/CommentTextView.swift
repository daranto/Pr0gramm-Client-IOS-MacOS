import SwiftUI
import UIKit

struct CommentTextView: UIViewRepresentable {
    let attributedText: AttributedString

    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.openURL = openURL

        let newText = displayText(for: textView)
        if textView.attributedText == nil || !textView.attributedText.isEqual(to: newText) {
            textView.attributedText = newText
            textView.invalidateIntrinsicContentSize()
        }

        textView.linkTextAttributes = [
            .foregroundColor: textView.tintColor ?? UIColor.link
        ]
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }

        let size = textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: ceil(size.height))
    }

    private func displayText(for textView: UITextView) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: NSAttributedString(attributedText))
        let fullRange = NSRange(location: 0, length: text.length)
        let linkColor = textView.tintColor ?? UIColor.link

        text.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        text.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            text.addAttribute(.foregroundColor, value: linkColor, range: range)
        }

        return text
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction

        init(openURL: OpenURLAction) {
            self.openURL = openURL
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }

            return UIAction { [openURL] _ in
                openURL(url)
            }
        }
    }
}
