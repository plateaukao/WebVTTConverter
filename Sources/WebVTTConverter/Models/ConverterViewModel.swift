import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
class ConverterViewModel: ObservableObject {
    @Published var vttDirectory: URL?
    @Published var coverImageURL: URL?
    @Published var coverImageData: Data?
    @Published var availableLanguages: [String] = []
    @Published var selectedMainLang: String = "-"
    @Published var selectedSubLang: String = "-"
    @Published var statusMessage: String = ""
    @Published var isConverting: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var directoryLabel: String = "No directory selected"

    private var tempDirectory: URL?

    var canConvert: Bool {
        vttDirectory != nil && selectedMainLang != "-" && !isConverting
    }

    var languageOptions: [(id: String, name: String)] {
        [("-", "-")] + availableLanguages
            .filter { !$0.hasSuffix("-forced") }
            .map { ($0, longLanguageName(for: $0)) }
    }

    // MARK: - Directory / ZIP Setup

    func setupDirectory(_ url: URL) {
        vttDirectory = url
        directoryLabel = url.lastPathComponent
        updateLanguages()
    }

    func setupZipFile(_ url: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WebVTTConverter_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            try extractZip(at: url, to: tempDir)
            tempDirectory = tempDir
            vttDirectory = tempDir
            directoryLabel = url.lastPathComponent
            updateLanguages()
        } catch {
            showErrorAlert("Failed to extract ZIP: \(error.localizedDescription)")
        }
    }

    func setupCover(_ url: URL) {
        coverImageURL = url
        coverImageData = try? Data(contentsOf: url)
    }

    func handleDrop(providers: [NSItemProvider], type: DropType) -> Bool {
        guard let provider = providers.first else { return false }

        // On macOS, Finder always provides files as public.file-url
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
            // Extract URL from the dropped item
            let url: URL?
            if let urlItem = item as? URL {
                url = urlItem
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
            } else {
                url = nil
            }

            guard let droppedURL = url else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .subtitle:
                    let ext = droppedURL.pathExtension.lowercased()
                    if ext == "zip" {
                        self.setupZipFile(droppedURL)
                    } else {
                        // Check if it's a directory
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: droppedURL.path, isDirectory: &isDir), isDir.boolValue {
                            self.setupDirectory(droppedURL)
                        }
                    }
                case .cover:
                    let ext = droppedURL.pathExtension.lowercased()
                    if ["png", "jpg", "jpeg", "webp", "tiff", "heic"].contains(ext) {
                        self.setupCover(droppedURL)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Conversion

    func convert() {
        guard let vttDir = vttDirectory, selectedMainLang != "-" else { return }

        isConverting = true
        statusMessage = "Converting..."

        let mainLang = selectedMainLang
        let subLang = selectedSubLang == "-" ? mainLang : selectedSubLang
        let coverData = coverImageData
        let coverExt = coverImageURL?.pathExtension.lowercased() ?? "jpg"

        Task.detached { [weak self] in
            do {
                let (_, title) = try WebVTTToHTMLConverter.convertToHTML(
                    directory: vttDir,
                    mainLang: mainLang,
                    subLang: subLang
                )

                // Build chapters
                let chapters = try self?.buildChapters(directory: vttDir, mainLang: mainLang, subLang: subLang) ?? []

                // Save dialog
                let saveURL = await self?.promptSaveLocation(title: title)
                guard let outputURL = saveURL else {
                    await MainActor.run { [weak self] in
                        self?.isConverting = false
                        self?.statusMessage = "Cancelled"
                    }
                    return
                }

                try EPUBWriter.createEPUB(
                    title: title,
                    chapters: chapters,
                    coverImageData: coverData,
                    coverImageExtension: (coverExt == "png") ? "png" : "jpg",
                    outputURL: outputURL
                )

                await MainActor.run { [weak self] in
                    self?.isConverting = false
                    self?.statusMessage = "Done! Saved to \(outputURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isConverting = false
                    self?.showErrorAlert("Conversion failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private

    private nonisolated func buildChapters(directory: URL, mainLang: String, subLang: String) throws -> [EPUBChapter] {
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

        let isSeries = vttFiles.contains { $0.lastPathComponent.contains("S02") }

        var chapters: [EPUBChapter] = []

        for (idx, vttFileURL) in vttFiles.enumerated() {
            var chapterTitle: String
            if isSeries, let series = WebVTTToHTMLConverter.getSeries(from: vttFileURL.lastPathComponent) {
                chapterTitle = "Season \(series.season)"
                if let epNum = Int(series.episode) {
                    chapterTitle += " Episode \(epNum)"
                } else {
                    chapterTitle += " \(series.episode)"
                }
            } else {
                chapterTitle = "Episode \(idx + 1)"
            }

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

            let content = WebVTTToHTMLConverter.convertFile(
                mainFileURL: vttFileURL,
                mainLang: mainLang,
                subLang: subLang,
                subFileURL: subFileURL
            )
            chapters.append(EPUBChapter(title: chapterTitle, htmlContent: content))
        }

        return chapters
    }

    private func updateLanguages() {
        guard let dir = vttDirectory else { return }
        do {
            let langs = try WebVTTToHTMLConverter.getLanguageList(from: dir)
            availableLanguages = langs
            selectedMainLang = "-"
            selectedSubLang = "-"
            if langs.count == 1 {
                selectedMainLang = langs[0]
            }
        } catch {
            showErrorAlert("Failed to read languages: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func promptSaveLocation(title: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "epub")!]
        panel.nameFieldStringValue = "\(title).epub"
        panel.canCreateDirectories = true

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    private func showErrorAlert(_ message: String) {
        errorMessage = message
        showError = true
        statusMessage = ""
    }

    private nonisolated func extractZip(at zipURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        // Use a temp location for full extraction, then flatten
        let tempExtract = destination.appendingPathComponent("_extract_temp")
        try fm.createDirectory(at: tempExtract, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: tempExtract)

        // Flatten: move all .vtt files to destination root
        let enumerator = fm.enumerator(at: tempExtract, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "vtt" {
                let destFile = destination.appendingPathComponent(fileURL.lastPathComponent)
                if !fm.fileExists(atPath: destFile.path) {
                    try fm.moveItem(at: fileURL, to: destFile)
                }
            }
        }
        try? fm.removeItem(at: tempExtract)
    }

    enum DropType {
        case subtitle
        case cover
    }

    deinit {
        if let temp = tempDirectory {
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
