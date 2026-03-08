// Pr0gramm/Pr0gramm/Features/Views/Search/SearchItemThumbnail.swift

import SwiftUI
import Kingfisher
import os

struct SearchItemThumbnail: View, Equatable {
    let item: Item
    let isSeen: Bool
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SearchItemThumbnail")

    static func == (lhs: SearchItemThumbnail, rhs: SearchItemThumbnail) -> Bool {
        lhs.item.id == rhs.item.id && lhs.isSeen == rhs.isSeen
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            KFImage(item.thumbnailUrl)
                .placeholder { Rectangle().fill(Material.ultraThin).overlay(ProgressView()) }
                .onFailure { error in SearchItemThumbnail.logger.error("KFImage fail \(item.id): \(error.localizedDescription)") }
                .cancelOnDisappear(true)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .aspectRatio(1.0, contentMode: .fit)
                .background(Material.ultraThin)
                .clipShape(.rect(cornerRadius: 5))
            
            if isSeen {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 18))
                    .padding(4)
            }
        }
    }
}
