import Foundation
import ZIPFoundation

struct EPUBChapter {
    let title: String
    let htmlContent: String
}

struct EPUBWriter {

    static func createEPUB(
        title: String,
        author: String = "WebVTT Converter",
        chapters: [EPUBChapter],
        coverImageData: Data? = nil,
        coverImageExtension: String = "jpg",
        outputURL: URL
    ) throws {
        let fm = FileManager.default

        // Remove existing file
        if fm.fileExists(atPath: outputURL.path) {
            try fm.removeItem(at: outputURL)
        }

        let archive = try Archive(url: outputURL, accessMode: .create)

        let uuid = UUID().uuidString

        // 1. mimetype (must be first, uncompressed)
        let mimetypeData = "application/epub+zip".data(using: .utf8)!
        try archive.addEntry(
            with: "mimetype",
            type: .file,
            uncompressedSize: Int64(mimetypeData.count),
            compressionMethod: .none,
            provider: { (position: Int64, size: Int) in
                let start = Int(position)
                let end = start + size
                return mimetypeData[start..<end]
            }
        )

        // 2. META-INF/container.xml
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        try addEntry(archive: archive, path: "META-INF/container.xml", content: containerXML)

        // 3. Cover image (if provided)
        let hasCover = coverImageData != nil
        if let coverData = coverImageData {
            let coverPath = "OEBPS/images/cover.\(coverImageExtension)"
            try archive.addEntry(
                with: coverPath,
                type: .file,
                uncompressedSize: Int64(coverData.count),
                provider: { (position: Int64, size: Int) in
                    let start = Int(position)
                    let end = start + size
                    return coverData[start..<end]
                }
            )
        }

        // 4. Stylesheet
        let css = """
        body { font-family: Georgia, serif; margin: 1em; line-height: 1.6; }
        h1 { text-align: center; margin-top: 2em; page-break-before: always; }
        h3 { margin: 0.3em 0; }
        .sub { font-size: 60%; color: gray; margin-top: 0.2em; margin-left: 1.0em; margin-bottom: 1.5em; }
        .cc { font-size: 70%; }
        .cover-page { text-align: center; page-break-after: always; }
        .cover-page img { max-width: 100%; max-height: 100%; }
        """
        try addEntry(archive: archive, path: "OEBPS/stylesheet.css", content: css)

        // 5. Chapter XHTML files
        for (idx, chapter) in chapters.enumerated() {
            let chapterXHTML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <title>\(escapeXML(chapter.title))</title>
              <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
            </head>
            <body>
              <h1>\(escapeXML(chapter.title))</h1>
              \(chapter.htmlContent)
            </body>
            </html>
            """
            try addEntry(archive: archive, path: "OEBPS/chapter\(idx + 1).xhtml", content: chapterXHTML)
        }

        // 6. Cover page (if cover image provided)
        if hasCover {
            let coverPageXHTML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
              <title>Cover</title>
              <link rel="stylesheet" type="text/css" href="stylesheet.css"/>
            </head>
            <body>
              <div class="cover-page">
                <img src="images/cover.\(coverImageExtension)" alt="Cover"/>
              </div>
            </body>
            </html>
            """
            try addEntry(archive: archive, path: "OEBPS/cover.xhtml", content: coverPageXHTML)
        }

        // 7. content.opf
        let coverMediaType = coverImageExtension == "png" ? "image/png" : "image/jpeg"
        var manifestItems = ""
        var spineItems = ""

        if hasCover {
            manifestItems += "    <item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            manifestItems += "    <item id=\"cover-image\" href=\"images/cover.\(coverImageExtension)\" media-type=\"\(coverMediaType)\" properties=\"cover-image\"/>\n"
            spineItems += "    <itemref idref=\"cover\"/>\n"
        }

        manifestItems += "    <item id=\"css\" href=\"stylesheet.css\" media-type=\"text/css\"/>\n"
        manifestItems += "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"

        for (idx, _) in chapters.enumerated() {
            manifestItems += "    <item id=\"chapter\(idx + 1)\" href=\"chapter\(idx + 1).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spineItems += "    <itemref idref=\"chapter\(idx + 1)\"/>\n"
        }

        let contentOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:\(uuid)</dc:identifier>
            <dc:title>\(escapeXML(title))</dc:title>
            <dc:creator>\(escapeXML(author))</dc:creator>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(iso8601Date())</meta>
          </metadata>
          <manifest>
        \(manifestItems)  </manifest>
          <spine>
        \(spineItems)  </spine>
        </package>
        """
        try addEntry(archive: archive, path: "OEBPS/content.opf", content: contentOPF)

        // 8. nav.xhtml (Table of Contents)
        var tocItems = ""
        if hasCover {
            tocItems += "      <li><a href=\"cover.xhtml\">Cover</a></li>\n"
        }
        for (idx, chapter) in chapters.enumerated() {
            tocItems += "      <li><a href=\"chapter\(idx + 1).xhtml\">\(escapeXML(chapter.title))</a></li>\n"
        }

        let navXHTML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head>
          <title>Table of Contents</title>
        </head>
        <body>
          <nav epub:type="toc">
            <h1>Table of Contents</h1>
            <ol>
        \(tocItems)    </ol>
          </nav>
        </body>
        </html>
        """
        try addEntry(archive: archive, path: "OEBPS/nav.xhtml", content: navXHTML)
    }

    private static func addEntry(archive: Archive, path: String, content: String) throws {
        let data = content.data(using: .utf8)!
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            provider: { (position: Int64, size: Int) in
                let start = Int(position)
                let end = start + size
                return data[start..<end]
            }
        )
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func iso8601Date() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
