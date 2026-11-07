import SwiftUI

/// PhotoPlus's own settings: NAS connection, rolling archive, storage and safety tier.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var archive: ArchiveEngine

    @State private var connectionMessage: String?
    @State private var isTesting = false
    @State private var confirmsFree = false
    @State private var isFreeing = false

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                archiveSection
                storageSection
                tierSection
            }
            .navigationTitle("设置")
            .confirmationDialog(
                "将从手机移除 \(archive.freeable.count) 张照片。原图保留在 NAS，手机上可随时查看。",
                isPresented: $confirmsFree,
                titleVisibility: .visible
            ) {
                Button("移除手机上的副本", role: .destructive) { free() }
                    .accessibilityIdentifier("confirm-free")
                Button("取消", role: .cancel) {}
            }
            .refreshable { await store.reload() }
            .contentMargins(.bottom, BottomBarMetrics.height, for: .scrollContent)
            .edgeFade(.bottom, color: Color(.systemGroupedBackground), height: 100)
        }
    }

    private var connectionSection: some View {
        Section {
            TextField("地址，如 http://192.168.1.10:8080", text: $settings.serverURLString)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("server-url")
            SecureField("访问令牌", text: $settings.token)
                .accessibilityIdentifier("server-token")
            Button {
                testConnection()
            } label: {
                HStack {
                    Text("测试连接")
                    Spacer()
                    if isTesting { ProgressView() }
                }
            }
            .disabled(settings.apiClient == nil || isTesting)
            .accessibilityIdentifier("test-connection")
            if let connectionMessage {
                Text(connectionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("connection-result")
            }
        } header: {
            Text("NAS 连接")
        }
    }

    private var archiveSection: some View {
        Section {
            Picker("保留在手机", selection: $settings.retentionMonths) {
                ForEach(AppSettings.retentionChoices, id: \.self) { Text("最近 \($0) 个月").tag($0) }
            }
            Toggle("打开 App 时自动归档", isOn: $settings.autoArchive)
            LabeledContent("待上传", value: "\(archive.pending.count) 张")
                .accessibilityIdentifier("pending-count")
            if case let .uploading(done, total) = archive.phase {
                ProgressView("正在上传 \(done)/\(total)", value: Double(done), total: Double(max(total, 1)))
                Button("暂停", role: .destructive) { archive.stop() }
            } else {
                Button("立即归档") { archive.start() }
                    .disabled(settings.apiClient == nil || archive.pending.isEmpty)
                    .accessibilityIdentifier("archive-now")
            }
            if let result = archive.lastResult {
                Text(result).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("archive-result")
            }
            ForEach(Array(archive.failures.prefix(3).enumerated()), id: \.offset) { _, failure in
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("滚动归档")
        } footer: {
            Text(archiveFooter)
        }
    }

    private var archiveFooter: String {
        var text = "早于保留期的原图会上传到 NAS。需要 App 留在前台。"
        if archive.skippedCount > 0 {
            text += " 有 \(archive.skippedCount) 项（视频、连拍或已编辑的照片）暂不归档，会一直保留在手机上。"
        }
        return text
    }

    private var storageSection: some View {
        Section {
            LabeledContent("手机可用空间", value: freeSpaceText)
            LabeledContent("NAS 已用", value: store.nasStats.map { PhotoFormat.bytes($0.totalBytes) } ?? "—")
            LabeledContent("NAS 上的照片", value: store.nasStats.map { "\($0.photoCount) 张" } ?? "—")
            LabeledContent("NAS 状态", value: nasStateText)
            Button("释放手机空间（\(archive.freeable.count) 张）") { confirmsFree = true }
                .disabled(archive.freeable.isEmpty || isFreeing)
                .accessibilityIdentifier("free-space")
        } header: {
            Text("存储")
        } footer: {
            Text("只移除 NAS 已确认保存的照片，iOS 还会再次请你确认。手机上移除的照片会先进入“最近删除”，保留 30 天，这段时间内不会腾出空间。")
        }
    }

    private var tierSection: some View {
        Section {
            Picker("新上传的照片", selection: $settings.tier) {
                ForEach(SafetyTier.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("安全等级")
        } footer: {
            Text("决定照片写入 NAS 上的哪个存储分组。实际副本数取决于 NAS 的硬盘配置，单盘时没有冗余。")
        }
    }

    private var nasStateText: String {
        switch store.nasState {
        case .notConfigured: settings.apiClient == nil ? "未配置" : "未连接"
        case .connecting: "正在连接…"
        case .connected: "已连接"
        case .unreachable: "无法连接"
        }
    }

    private var freeSpaceText: String {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map(PhotoFormat.bytes) ?? "—"
    }

    private func testConnection() {
        guard let api = settings.apiClient else { return }
        isTesting = true
        connectionMessage = nil
        Task {
            defer { isTesting = false }
            do {
                let stats = try await api.stats()
                connectionMessage = "连接成功，NAS 上有 \(stats.photoCount) 张照片"
                await store.reload()
            } catch {
                connectionMessage = "连接失败：\(error.localizedDescription)"
                await store.refreshRemote()
            }
        }
    }

    private func free() {
        isFreeing = true
        Task {
            await archive.freeSpace()
            isFreeing = false
        }
    }
}
