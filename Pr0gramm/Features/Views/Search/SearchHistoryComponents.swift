// Pr0gramm/Pr0gramm/Features/Views/Search/SearchHistoryComponents.swift

import SwiftUI

// MARK: - Search History View

struct SearchHistoryView: View {
    let searchHistory: [String]
    let onSelectTerm: (String) -> Void
    let onDeleteTerm: (String) -> Void
    let onClearAll: () -> Void
    
    var body: some View {
        if !searchHistory.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Zuletzt gesucht")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClearAll) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                            Text("Alle löschen")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                // History Items
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(searchHistory.enumerated()), id: \.element) { index, term in
                        SearchHistoryRow(
                            term: term,
                            onSelect: { onSelectTerm(term) },
                            onDelete: { onDeleteTerm(term) }
                        )
                        
                        if index < searchHistory.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Search History Row

struct SearchHistoryRow: View {
    let term: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            
            Text(term)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.red.opacity(isHovered ? 1.0 : 0.8))
                    .clipShape(Circle())
                    .scaleEffect(isHovered ? 1.1 : 1.0)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(isHovered ? .gray.opacity(0.05) : .clear)
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
