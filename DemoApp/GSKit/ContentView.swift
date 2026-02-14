//
//  ContentView.swift
//  GSKit
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var showingImporter = false
    @State private var plyVertexCount: Int?

    @ViewBuilder
    private var loadingSplatPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
                .progressViewStyle(.circular)
            Text("Loading splats...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    var body: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Gaussian Splatting Viewer")
                        .font(.title2.weight(.semibold))

                    Text("A macOS 26 RealityKit gaussian splat experiment with fly-through navigation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    sidebarSection("File Selection") {
                        if let url = appState.selectedPLYURL {
                            Text(url.lastPathComponent)
                                .font(.callout.weight(.medium))
                                .lineLimit(3)
                                .textSelection(.enabled)

                            if let count = plyVertexCount {
                                Label("\(count.formatted(.number.grouping(.automatic))) vertices", systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Button("Open .PLY…") {
                                    showingImporter = true
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Close File") {
                                    appState.selectedPLYURL = nil
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Text("No file selected")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Button("Open .PLY…") {
                                showingImporter = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Menu")
            .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            Group {
                if let url = appState.selectedPLYURL {
                    GSView(url: url) {
                        loadingSplatPlaceholder
                            .padding()
                    }
                    .clipShape(.rect(cornerRadius: 14))
                } else {
                    ContentUnavailableView(
                        "No PLY Selected",
                        systemImage: "point.3.filled.connected.trianglepath.dotted",
                        description: Text("Open a binary 3DGS .ply file from the sidebar to inspect it in RealityKit.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.08))
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: appState.selectedPLYURL) {
            plyVertexCount = nil
            guard let url = appState.selectedPLYURL else { return }

            let count = await Task.detached(priority: .utility) {
                await Self.readPLYVertexCount(url: url)
            }.value
            plyVertexCount = count
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "ply") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                appState.selectedPLYURL = urls.first
            case .failure:
                break
            }
        }
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static func readPLYVertexCount(url: URL) -> Int? {
        let didStartAccess = url.isFileURL ? url.startAccessingSecurityScopedResource() : false
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let prefix = try handle.read(upToCount: 1_048_576) ?? Data()
            let headerText = String(decoding: prefix, as: UTF8.self)

            for rawLine in headerText.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("element vertex ") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 3, let count = Int(parts[2]) {
                        return count
                    }
                }
                if line == "end_header" {
                    break
                }
            }
        } catch {
            return nil
        }

        return nil
    }
}
