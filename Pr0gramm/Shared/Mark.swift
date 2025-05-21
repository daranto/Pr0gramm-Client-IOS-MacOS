// Pr0gramm/Pr0gramm/Shared/Mark.swift
// --- START OF COMPLETE FILE ---

import SwiftUI

/// Represents the user ranks (Marks) on pr0gramm.
/// The `rawValue` corresponds to the integer value provided by the API.
/// Colors are based on the reference repository: https://github.com/NickAtGit/pr0gramm-iOS/blob/main/pr0gramm/Model/User.swift
enum Mark: Int, Codable, CaseIterable, Identifiable {
    case schwuchtel = 0
    case neuschwuchtel = 1
    case altschwuchtel = 2
    case administrator = 3
    case gebannt = 4
    case moderator = 5
    case fliesentisch = 6
    case lebendeLegende = 7
    case wichtel = 8
    case edlerSpender = 9          // API/Repo name: 'spender'
    case mittelaltschwuchtel = 10
    case ehemaligerModerator = 11  // API/Repo name: 'altmod'
    case communityHelfer = 12      // API/Repo name: 'helfer'
    case nutzerBot = 13            // API/Repo name: 'bot'
    case systemBot = 14            // API/Repo name: 'sysbot'
    case ehemaligerHelfer = 15     // API/Repo name: 'althelfer'
    case unbekannt = -1            // Fallback for unknown values

    /// Safe initializer that defaults to `.unbekannt` if the raw value doesn't match a known case.
    init(rawValue: Int) {
        self = Mark.allCases.first { $0.rawValue == rawValue } ?? .unbekannt
    }

    var id: Int { self.rawValue }

    /// Returns the display name for the rank.
    var displayName: String {
        switch self {
        case .schwuchtel: return "Schwuchtel"
        case .neuschwuchtel: return "Neuschwuchtel"
        case .altschwuchtel: return "Altschwuchtel"
        case .administrator: return "Administrator"
        case .gebannt: return "Gebannt"
        case .moderator: return "Moderator"
        case .fliesentisch: return "Fliesentischbesitzer"
        case .lebendeLegende: return "Legende"
        case .wichtel: return "Wichtel"
        case .edlerSpender: return "Edler Spender"
        case .mittelaltschwuchtel: return "Mittelaltschwuchtel"
        case .ehemaligerModerator: return "Altmoderator"
        case .communityHelfer: return "Community-Helfer"
        case .nutzerBot: return "Bot (Nutzer)"
        case .systemBot: return "Bot (System)"
        case .ehemaligerHelfer: return "Althelfer"
        case .unbekannt: return "Unbekannt (\(self.rawValue))" // Include raw value for debugging
        }
    }

    /// Returns the associated color for the rank based on the reference repository.
    var displayColor: Color {
        switch self {
        case .schwuchtel:           return Color(hex: 0xffffff)
        case .neuschwuchtel:        return Color(hex: 0xe108e9)
        case .altschwuchtel:        return Color(hex: 0x5bb91c)
        case .administrator:        return Color(hex: 0xff9900)
        case .gebannt:              return Color(hex: 0x444444)
        case .moderator:            return Color(hex: 0x008fff)
        case .fliesentisch:         return Color(hex: 0x6c432b)
        case .lebendeLegende:       return Color(hex: 0x1cb992)
        case .wichtel:              return Color(hex: 0xc52b2f)
        case .edlerSpender:         return Color(hex: 0x1cb992)
        case .mittelaltschwuchtel:  return Color(hex: 0xaddc8d)
        case .ehemaligerModerator:  return Color(hex: 0x7fc7ff)
        case .communityHelfer:      return Color(hex: 0xc52b2f)
        case .nutzerBot:            return Color(hex: 0x10366f)
        case .systemBot:            return Color(hex: 0xffc166)
        case .ehemaligerHelfer:     return Color(hex: 0xea9fa1)
        case .unbekannt:            return .secondary
        }
    }
}

/// Helper extension to create a SwiftUI `Color` from a hex integer (e.g., 0xFF0000 for red).
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// --- UserMarkView hierher verschoben ---
struct UserMarkView: View {
    let markValue: Int?
    let showName: Bool

    private var markEnum: Mark
    private var markColor: Color { markEnum.displayColor }
    private var markName: String { markEnum.displayName }

    init(markValue: Int?, showName: Bool = true) {
        self.markValue = markValue
        self.markEnum = Mark(rawValue: markValue ?? -1) // Sichere Initialisierung
        self.showName = showName
    }

    static func getMarkName(for mark: Int) -> String { Mark(rawValue: mark).displayName }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(markColor)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 0.5))
                .frame(width: 8, height: 8)
            if showName {
                Text(markName)
                    .font(UIConstants.subheadlineFont) // Verwendung von UIConstants
                    .foregroundColor(.secondary)
            }
        }
    }
}
// --- ENDE UserMarkView ---
// --- END OF COMPLETE FILE ---
