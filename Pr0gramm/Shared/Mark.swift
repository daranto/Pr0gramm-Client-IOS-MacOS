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
        // Hex values converted from reference repo (RRGGBB → 0.0–1.0)
        case .schwuchtel:           return Color(hex: 0xffffff) // White
        case .neuschwuchtel:        return Color(hex: 0xe108e9) // Magenta
        case .altschwuchtel:        return Color(hex: 0x5bb91c) // Green
        case .administrator:        return Color(hex: 0xff9900) // Orange
        case .gebannt:              return Color(hex: 0x444444) // Dark Gray
        case .moderator:            return Color(hex: 0x008fff) // Blue
        case .fliesentisch:         return Color(hex: 0x6c432b) // Brown
        case .lebendeLegende:       return Color(hex: 0x1cb992) // Teal
        case .wichtel:              return Color(hex: 0xc52b2f) // Dark Red
        case .edlerSpender:         return Color(hex: 0x1cb992) // Teal (same as Legende)
        case .mittelaltschwuchtel:  return Color(hex: 0xaddc8d) // Light Green
        case .ehemaligerModerator:  return Color(hex: 0x7fc7ff) // Light Blue
        case .communityHelfer:      return Color(hex: 0xc52b2f) // Dark Red (same as Wichtel)
        case .nutzerBot:            return Color(hex: 0x10366f) // Dark Blue
        case .systemBot:            return Color(hex: 0xffc166) // Peach
        case .ehemaligerHelfer:     return Color(hex: 0xea9fa1) // Pink
        case .unbekannt:            return .secondary          // Fallback color
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
