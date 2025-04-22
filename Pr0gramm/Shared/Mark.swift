// Mark.swift

import SwiftUI // Import für Color

/// Repräsentiert die Benutzer-Ränge (Marks) auf pr0gramm.
/// Die RawValues entsprechen den von der API gelieferten Integer-Werten.
/// Farben basieren auf https://github.com/NickAtGit/pr0gramm-iOS/blob/main/pr0gramm/Model/User.swift
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
    case edlerSpender = 9  // 'spender' im Repo
    case mittelaltschwuchtel = 10
    case ehemaligerModerator = 11 // 'altmod' im Repo
    case communityHelfer = 12   // 'helfer' im Repo
    case nutzerBot = 13         // 'bot' im Repo
    case systemBot = 14         // 'sysbot' im Repo
    case ehemaligerHelfer = 15  // 'althelfer' im Repo
    case unbekannt = -1         // Fallback

    // Sicherer Initializer
    init(rawValue: Int) {
        self = Mark.allCases.first { $0.rawValue == rawValue } ?? .unbekannt
    }

    var id: Int { self.rawValue }

    /// Gibt den Anzeigenamen für den Rang zurück.
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
        case .unbekannt: return "Unbekannt (\(self.rawValue))"
        }
    }

    /// Gibt die zugehörige Farbe für den Rang zurück (basierend auf Referenz-Repo).
    var displayColor: Color {
        switch self {
        // Hex‑Werte aus Repo umgerechnet (RRGGBB → Double 0.0–1.0)
        case .schwuchtel:           return Color(hex: 0xffffff) // Weiß → SwiftUI .white
        case .neuschwuchtel:        return Color(hex: 0xe108e9) // Magenta
        case .altschwuchtel:        return Color(hex: 0x5bb91c) // Grün
        case .administrator:        return Color(hex: 0xff9900) // Orange → SwiftUI .orange ist nah genug
        case .gebannt:              return Color(hex: 0x444444) // Dunkelgrau
        case .moderator:            return Color(hex: 0x008fff) // Blau
        case .fliesentisch:         return Color(hex: 0x6c432b) // Braun → SwiftUI .brown
        case .lebendeLegende:       return Color(hex: 0x1cb992) // Türkis / Teal
        case .wichtel:              return Color(hex: 0xc52b2f) // Dunkelrot
        case .edlerSpender:         return Color(hex: 0x1cb992) // Türkis / Teal
        case .mittelaltschwuchtel:  return Color(hex: 0xaddc8d) // Hellgrün
        case .ehemaligerModerator:  return Color(hex: 0x7fc7ff) // Hellblau
        case .communityHelfer:      return Color(hex: 0xc52b2f) // Dunkelrot
        case .nutzerBot:            return Color(hex: 0x10366f) // Dunkelblau
        case .systemBot:            return Color(hex: 0xffc166) // Pfirsich
        case .ehemaligerHelfer:     return Color(hex: 0xea9fa1) // Rosa
        case .unbekannt:            return .secondary          // Fallback
        }
    }
}

// Hilfserweiterung, um Color aus Hex zu erstellen (wie im Repo, aber vereinfacht)
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
