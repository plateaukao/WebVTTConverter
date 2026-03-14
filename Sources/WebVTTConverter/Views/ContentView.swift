import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ConverterViewModel()
    @State private var subtitleDropHighlight = false
    @State private var coverDropHighlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Instructions
            Text("1. Choose subtitle directory or a zip file\n2. Setup main language and sub language\n3. Click Convert button")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            // Subtitle source section
            GroupBox(label: Label("Subtitle Source", systemImage: "doc.text")) {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Subtitle Directory") {
                            pickDirectory()
                        }
                        Button("Subtitle Zip File") {
                            pickZipFile()
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Drop zone
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                subtitleDropHighlight ? Color.accentColor : Color.gray.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2, dash: [6])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(subtitleDropHighlight ? Color.accentColor.opacity(0.1) : Color.clear)
                            )

                        VStack(spacing: 4) {
                            Image(systemName: "arrow.down.doc")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text(viewModel.directoryLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                    }
                    .frame(height: 70)
                    .onDrop(of: [.fileURL], isTargeted: $subtitleDropHighlight) { providers in
                        viewModel.handleDrop(providers: providers, type: .subtitle)
                    }
                }
                .padding(8)
            }

            // Cover image section
            GroupBox(label: Label("Cover Image (Optional)", systemImage: "photo")) {
                HStack(spacing: 12) {
                    Button("Choose Cover Image") {
                        pickCoverImage()
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                coverDropHighlight ? Color.accentColor : Color.gray.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2, dash: [6])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(coverDropHighlight ? Color.accentColor.opacity(0.1) : Color.clear)
                            )

                        if let coverData = viewModel.coverImageData,
                           let nsImage = NSImage(data: coverData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(4)
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Text("Drop image here")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(width: 80, height: 60)
                    .onDrop(of: [.fileURL], isTargeted: $coverDropHighlight) { providers in
                        viewModel.handleDrop(providers: providers, type: .cover)
                    }
                }
                .padding(8)
            }

            // Language selection
            GroupBox(label: Label("Languages", systemImage: "globe")) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Main language:")
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $viewModel.selectedMainLang) {
                            ForEach(viewModel.languageOptions, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack {
                        Text("Second language:")
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $viewModel.selectedSubLang) {
                            ForEach(viewModel.languageOptions, id: \.id) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(8)
            }

            // Convert button + status
            HStack {
                Button(action: { viewModel.convert() }) {
                    HStack {
                        if viewModel.isConverting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(viewModel.isConverting ? "Converting..." : "Convert to EPUB")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canConvert)
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.callout)
                    .foregroundColor(viewModel.statusMessage.hasPrefix("Done") ? .green : .secondary)
            }
        }
        .padding(20)
        .frame(width: 420)
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - File Pickers

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select directory containing VTT subtitle files"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setupDirectory(url)
        }
    }

    private func pickZipFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.zip]
        panel.message = "Select subtitle zip file"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setupZipFile(url)
        }
    }

    private func pickCoverImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "Select cover image"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setupCover(url)
        }
    }
}
