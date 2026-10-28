#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI

struct StorageWorkspaceView: View {
    @ObservedObject var model: StorageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Choose Folder…", action: chooseFolder)
                Button("Up") { model.goUp() }.disabled(model.currentURL.path == "/")
                Button("Refresh") { model.rescan() }.disabled(model.isLoading)
                if model.isLoading { Button("Cancel") { model.cancelScan() } }
                Spacer()
                Picker("Sort", selection: $model.sortBy) {
                    ForEach(StorageViewModel.SortOption.allCases, id: \.self) { option in
                        Text(L10n.string(option.rawValue)).tag(option)
                    }
                }.frame(width: 220)
            }
            Text(model.currentURL.path).font(.caption).textSelection(.enabled)
            TextField("Search files", text: $model.filterText)
            Toggle("Deep Scan", isOn: $model.deepScanEnabled)
            if model.isLoading {
                ProgressView(value: model.indexingProgress)
                Text(L10n.string(model.indexingLabel)).font(.caption).foregroundStyle(.secondary)
            }
            Text(model.used.formatted(.byteCount(style: .file)) + " / " + model.total.formatted(.byteCount(style: .file)))
                .font(.caption).monospacedDigit()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.filteredAndSortedEntries.prefix(500))) { entry in
                        row(entry)
                        Divider()
                    }
                }
            }.frame(height: 360)
            if model.filteredAndSortedEntries.count > 500 {
                Text("Showing the first 500 items. Use search to narrow the results.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array((model.scanErrors + model.removalIssues).prefix(5))) { issue in
                Text(issue.message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ entry: StorageEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isDirectory ? "folder" : "doc")
            Button {
                if entry.isDirectory { model.open(entry) } else { model.reveal(entry) }
            } label: {
                Text(entry.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Text(entry.size.formatted(.byteCount(style: .file))).font(.caption).monospacedDigit()
            Button("In Finder") { model.reveal(entry) }
            Button("Move to Trash", role: .destructive) { model.requestRemoval(entry) }
                .disabled(entry.isSystemProtected || model.isRemoving)
        }.padding(.vertical, 7)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.open(StorageEntry(url: url, size: 0, isDirectory: true))
        }
    }
}
#endif
