import Foundation

struct Caption {
    var start: TimeInterval  // seconds
    var end: TimeInterval    // seconds
    var text: String
    var identifier: String?

    var startMilliseconds: Int {
        Int(start * 1000)
    }

    var endMilliseconds: Int {
        Int(end * 1000)
    }

    static func parseTimestamp(_ str: String) -> TimeInterval? {
        // Formats: HH:MM:SS.mmm or MM:SS.mmm
        let cleaned = str.trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        let lastPart = parts.last!.replacingOccurrences(of: ",", with: ".")
        let secParts = lastPart.components(separatedBy: ".")
        guard secParts.count == 2,
              let seconds = Int(secParts[0]),
              let millis = Int(secParts[1]) else { return nil }

        if parts.count == 3 {
            guard let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            return TimeInterval(hours * 3600 + minutes * 60 + seconds) + TimeInterval(millis) / 1000.0
        } else {
            guard let minutes = Int(parts[0]) else { return nil }
            return TimeInterval(minutes * 60 + seconds) + TimeInterval(millis) / 1000.0
        }
    }
}
