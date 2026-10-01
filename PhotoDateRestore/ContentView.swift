import SwiftUI
import PhotosUI
import Photos

struct ContentView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var results: [PhotoDateInfo] = []
    @State private var allowExifFallback = false
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("恢复策略") {
                    Toggle("允许 EXIF 兜底", isOn: $allowExifFallback)
                    Text("默认关闭。优先使用 Photos 提供的系统原始日期；取不到时，只有开启此选项才使用 EXIF DateTimeOriginal。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("选择照片") {
                    PhotosPicker(selection: $items, maxSelectionCount: nil, matching: .images) {
                        Label("选择照片", systemImage: "photo.on.rectangle.angled")
                    }
                    Button("分析，不修改") { Task { await analyze() } }
                        .disabled(items.isEmpty || busy)
                }
                if !results.isEmpty {
                    Section("分析结果") {
                        Text("已分析：\(results.count) 张")
                        Text("系统原始日期可用：\(results.filter { $0.systemOriginal != nil }.count) 张")
                        Text("EXIF 可用：\(results.filter { $0.exifOriginal != nil }.count) 张")
                        ForEach(results.prefix(10)) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.filename).font(.headline)
                                Text("当前：\(fmt(r.current))")
                                Text("系统原始：\(fmt(r.systemOriginal))")
                                Text("EXIF：\(fmt(r.exifOriginal))")
                                Text("将使用：\(fmt(r.chosen(allowExif: allowExifFallback)))")
                            }.font(.caption)
                        }
                    }
                    Section("修改") {
                        Button("测试恢复前 3 张") { Task { await restore(limit: 3) } }.disabled(busy)
                        Button("恢复全部可恢复照片") { Task { await restore(limit: nil) } }.disabled(busy)
                    }
                }
                if !message.isEmpty { Section { Text(message) } }
            }
            .navigationTitle("Photo Date Restore")
        }
    }

    private func fmt(_ date: Date?) -> String {
        guard let date else { return "不可用" }
        return date.formatted(date: .numeric, time: .standard)
    }

    @MainActor private func analyze() async {
        busy = true; message = "正在分析…"; results = []
        var out: [PhotoDateInfo] = []
        for item in items {
            if let id = item.itemIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                out.append(await PhotoDateService.inspect(asset: asset))
            }
        }
        results = out; busy = false
        message = "分析完成。请先核对日期，再测试恢复 3 张。"
    }

    @MainActor private func restore(limit: Int?) async {
        busy = true
        let all = results.filter { $0.chosen(allowExif: allowExifFallback) != nil }
        let candidates = limit.map { Array(all.prefix($0)) } ?? all
        do {
            try await PhotoDateService.apply(candidates, allowExifFallback: allowExifFallback)
            message = "已修改 \(candidates.count) 张。请立即在系统“照片”中核对；确认与手工“复原”一致后再批量执行。"
        } catch {
            message = "修改失败：\(error.localizedDescription)"
        }
        busy = false
    }
}
