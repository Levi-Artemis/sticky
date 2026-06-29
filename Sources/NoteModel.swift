import Foundation
import SwiftUI

struct NoteModel: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var colorIndex = 0
    var isPinned = false
    var fontSize = 14.0
    var positionX = 300.0
    var positionY = 300.0
    var width = 260.0
    var height = 260.0

    static let colors: [Color] = [
        Color(red: 1, green: 0.98, blue: 0.7),
        Color(red: 0.7, green: 0.9, blue: 0.7),
        Color(red: 0.7, green: 0.8, blue: 1.0),
        Color(red: 1, green: 0.75, blue: 0.8),
        Color(red: 0.85, green: 0.75, blue: 1.0),
    ]

    var color: Color {
        Self.colors[colorIndex % Self.colors.count]
    }

    mutating func nextColor() {
        colorIndex = (colorIndex + 1) % Self.colors.count
    }
}
