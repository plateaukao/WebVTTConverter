import Foundation

struct WebVTTConvertError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct WebVTTToHTMLConverter {

    /// Get list of available languages from VTT filenames in a directory
    static func getLanguageList(from directory: URL) throws -> [String] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let vttFiles = files.filter { $0.pathExtension.lowercased() == "vtt" }

        var langs = Set<String>()
        for file in vttFiles {
            // Pattern: Name.LangCode.vtt
            let name = file.deletingPathExtension().lastPathComponent
            if let dotIndex = name.lastIndex(of: ".") {
                let lang = String(name[name.index(after: dotIndex)...])
                langs.insert(lang)
            }
        }
        return langs.sorted()
    }

    /// Get the film/show name from VTT filenames
    static func getFilmName(from directory: URL) throws -> String {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let vttFiles = files.filter { $0.pathExtension.lowercased() == "vtt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = vttFiles.first else {
            throw WebVTTConvertError(message: "No VTT files found")
        }
        let name = first.deletingPathExtension().deletingPathExtension().lastPathComponent
        return name.components(separatedBy: ".").first ?? name
    }

    /// Parse S##E## pattern from filename
    static func getSeries(from filename: String) -> (season: Int, episode: String)? {
        let segments = filename.components(separatedBy: ".")
        for (idx, segment) in segments.enumerated() {
            // S01E01 format
            if segment.count == 6,
               segment.hasPrefix("S"),
               segment[segment.index(segment.startIndex, offsetBy: 3)] == "E" {
                let seasonStr = segment[segment.index(segment.startIndex, offsetBy: 1)...segment.index(segment.startIndex, offsetBy: 2)]
                let episodeStr = segment[segment.index(segment.startIndex, offsetBy: 4)...segment.index(segment.startIndex, offsetBy: 5)]
                if let season = Int(seasonStr), let episode = Int(episodeStr) {
                    return (season, String(episode))
                }
            }
            // S# format with next segment as episode
            if segment.count == 3, segment.hasPrefix("S"),
               segment[segment.index(after: segment.startIndex)].isNumber {
                let seasonStr = String(segment.dropFirst())
                if let season = Int(seasonStr), idx + 1 < segments.count {
                    return (season, segments[idx + 1])
                }
            }
        }
        return nil
    }

    /// Convert a single VTT file pair (main + sub language) to HTML string
    static func convertFile(mainFileURL: URL, mainLang: String, subLang: String, subFileURL: URL?) -> String {
        var html = ""

        guard let mainCaptions = try? WebVTTParser.parse(fileURL: mainFileURL) else {
            return html
        }

        // Single language mode
        guard mainLang != subLang, let subFileURL = subFileURL,
              let subCaptions = try? WebVTTParser.parse(fileURL: subFileURL) else {
            for caption in mainCaptions {
                let text = caption.text.replacingOccurrences(of: "&lrm;", with: "")
                html += "<h3>\(text)</h3>\n"
            }
            return html
        }

        // Dual language mode
        var indexMain = 0
        var indexSub = 0
        let threshold = 400 // ms
        var lastMainStart = 0

        while indexMain < mainCaptions.count {
            while indexSub < subCaptions.count {
                let captionMain = mainCaptions[indexMain]
                let captionSub = subCaptions[indexSub]
                let mainStart = captionMain.startMilliseconds
                let subStart = captionSub.startMilliseconds

                if mainStart - threshold <= subStart {
                    // Paragraph break for gaps > 5 seconds
                    if mainStart > lastMainStart + 5000 {
                        html += "<p/>\n"
                    }
                    let text = captionMain.text
                        .replacingOccurrences(of: "&lrm;", with: "")
                        .replacingOccurrences(of: "\n", with: " ")

                    if text.hasPrefix("[") && text.hasSuffix("]") {
                        html += "<div class=\"cc\">\(text)</div>\n"
                    } else {
                        html += "\(text)\n"
                    }
                    lastMainStart = mainStart
                    break
                } else {
                    let subText = captionSub.text
                        .replacingOccurrences(of: "&lrm;", with: "")
                        .replacingOccurrences(of: "\n", with: " ")
                    html += "<div class=\"sub\">\(subText)</div>\n"
                    indexSub += 1
                }
            }
            indexMain += 1
        }

        // Remaining sub captions
        while indexSub < subCaptions.count {
            html += "\(subCaptions[indexSub].text)\n"
            indexSub += 1
        }

        return html
    }

    /// Convert all VTT files in a directory to a single HTML string
    static func convertToHTML(
        directory: URL,
        mainLang: String,
        subLang: String
    ) throws -> (html: String, title: String) {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        let escapedLang = NSRegularExpression.escapedPattern(for: mainLang)
        let pattern = ".*\(escapedLang)\\.vtt$"
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)

        var vttFiles = files.filter { url in
            let name = url.lastPathComponent
            return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        vttFiles.sort { $0.lastPathComponent < $1.lastPathComponent }

        guard !vttFiles.isEmpty else {
            throw WebVTTConvertError(message: "No VTT files found for language '\(mainLang)'")
        }

        let title = try getFilmName(from: directory)

        // Check if it's a series (has S02 in any filename)
        let isSeries = vttFiles.contains { $0.lastPathComponent.contains("S02") }

        var html = "<html>\n<head>\n<title>\(title)</title>\n"
        html += "<style> .sub { font-size: 60%; color: gray; margin-top: 0.2em; margin-left: 1.0em; margin-bottom:1.5em; } .cc { font-size: 70%}</style>\n"
        html += "</head>\n<body>\n"

        var chapters: [(title: String, content: String)] = []

        for (idx, vttFileURL) in vttFiles.enumerated() {
            var chapterTitle: String

            if isSeries {
                if let series = getSeries(from: vttFileURL.lastPathComponent) {
                    chapterTitle = "Season \(series.season)"
                    if let epNum = Int(series.episode) {
                        chapterTitle += " Episode \(epNum)"
                    } else {
                        chapterTitle += " \(series.episode)"
                    }
                } else {
                    chapterTitle = "Episode \(idx + 1)"
                }
            } else {
                chapterTitle = "Episode \(idx + 1)"
            }

            html += "<div class=\"chapter\"><h1>\(chapterTitle)</h1></div>\n<br>\n<br>\n"

            // Build sub language file URL
            var subFileURL: URL? = nil
            if mainLang != subLang {
                let subFileName = vttFileURL.lastPathComponent.replacingOccurrences(
                    of: "\(mainLang).vtt",
                    with: "\(subLang).vtt"
                )
                let candidateURL = directory.appendingPathComponent(subFileName)
                if fm.fileExists(atPath: candidateURL.path) {
                    subFileURL = candidateURL
                }
            }

            let chapterContent = convertFile(
                mainFileURL: vttFileURL,
                mainLang: mainLang,
                subLang: subLang,
                subFileURL: subFileURL
            )
            html += chapterContent
            chapters.append((title: chapterTitle, content: chapterContent))
        }

        html += "</body>\n</html>"

        return (html, title)
    }
}
