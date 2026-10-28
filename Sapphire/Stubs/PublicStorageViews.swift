#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI

struct StorageDetailView: View {
    @StateObject private var model = StorageViewModel()
    var body: some View {
        ScrollView { StorageWorkspaceView(model: model).padding(16) }
            .frame(width: 560, height: 500)
            .onAppear { model.refreshFromCache() }
            .onDisappear { model.cancelScan() }
            .alert("Move item to Trash?", isPresented: $model.confirmingRemoval) {
                Button("Move to Trash", role: .destructive) { model.removeConfirmed() }
                Button("Cancel", role: .cancel) { model.cancelRemovalRequest() }
            } message: { Text(model.removalMessage) }
    }
}

struct StorageWidgetView: View {
    @State private var capacity: (total: Int64, free: Int64)?
    @State private var refreshing = false
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage", systemImage: "internaldrive").font(.headline)
            if let capacity, capacity.total > 0 {
                let used = max(0, capacity.total - capacity.free)
                Text(used.formatted(.byteCount(style: .file))).font(.title2).monospacedDigit()
                ProgressView(value: Double(used), total: Double(capacity.total))
                Text(L10n.string("Available") + ": " + capacity.free.formatted(.byteCount(style: .file)))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Storage unavailable").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(width: 210, alignment: .leading)
            .task { await refresh() }
            .onReceive(timer) { _ in Task { await refresh() } }
    }

    @MainActor private func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let result = await Task.detached(priority: .utility) { () -> (Int64, Int64)? in
            guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let total = attributes[.systemSize] as? NSNumber,
                  let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
            return (max(0, total.int64Value), max(0, min(total.int64Value, free.int64Value)))
        }.value
        guard !Task.isCancelled else { return }
        capacity = result.map { (total: $0.0, free: $0.1) }
    }
}
#endif
