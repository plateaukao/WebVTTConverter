import Foundation

struct WebVTTParser {
    enum ParseError: LocalizedError {
        case malformedFile(String)
        case malformedCaption(String)

        var errorDescription: String? {
            switch self {
            case .malformedFile(let msg): return "Malformed file: \(msg)"
            case .malformedCaption(let msg): return "Malformed caption: \(msg)"
            }
        }
    }

    static func parse(fileURL: URL) throws -> [Caption] {
        let data = try Data(contentsOf: fileURL)
        var content: String
        // Handle BOM
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            content = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        } else {
            content = String(data: data, encoding: .utf8) ?? ""
        }

        let lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else {
            throw ParseError.malformedFile("Empty file")
        }

        // Validate WEBVTT header
        guard lines[0].hasPrefix("WEBVTT") else {
            throw ParseError.malformedFile("Missing WEBVTT header")
        }

        return parseBlocks(lines: lines)
    }

    private static func parseBlocks(lines: [String]) -> [Caption] {
        var captions: [Caption] = []
        var currentCaption: Caption?
        var foundTimeline = false
        var skipHeader = true

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip header block
            if skipHeader {
                if trimmed.isEmpty {
                    skipHeader = false
                }
                continue
            }

            // Skip NOTE and STYLE blocks
            if trimmed.hasPrefix("NOTE") || trimmed.hasPrefix("STYLE") {
                currentCaption = nil
                foundTimeline = false
                continue
            }

            if trimmed.contains("-->") {
                // Timeline line
                let parts = trimmed.components(separatedBy: "-->")
                guard parts.count >= 2 else { continue }

                let startStr = parts[0].trimmingCharacters(in: .whitespaces)
                let endRaw = parts[1].trimmingCharacters(in: .whitespaces)
                // End may have position info after the timestamp
                let endStr = endRaw.components(separatedBy: " ").first ?? endRaw

                guard let startTime = Caption.parseTimestamp(startStr),
                      let endTime = Caption.parseTimestamp(endStr) else { continue }

                if let existing = currentCaption, !existing.text.isEmpty {
                    captions.append(existing)
                }
                currentCaption = Caption(start: startTime, end: endTime, text: "")
                foundTimeline = true
            } else if trimmed.isEmpty {
                // Blank line = end of caption block
                if let caption = currentCaption, foundTimeline, !caption.text.isEmpty {
                    captions.append(caption)
                    currentCaption = nil
                    foundTimeline = false
                }
            } else if foundTimeline {
                // Caption text line
                if currentCaption != nil {
                    if currentCaption!.text.isEmpty {
                        currentCaption!.text = trimmed
                    } else {
                        currentCaption!.text += "\n" + trimmed
                    }
                }
            }
            // Else: identifier line or other non-timeline text before --> (skip)
        }

        // Don't forget last caption
        if let caption = currentCaption, !caption.text.isEmpty {
            captions.append(caption)
        }

        return captions
    }
}
