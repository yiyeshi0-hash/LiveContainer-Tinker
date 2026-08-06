import SwiftUI

struct TinkerCenterView: View {
    @EnvironmentObject var sharedModel: SharedModel

    private let statuses = ["All", "Works", "Partial", "Broken", "Untested"]
    private let statusColors: [String: Color] = [
        "Works": .green,
        "Partial": .orange,
        "Broken": .red,
        "Untested": .secondary,
    ]

    @State private var searchText = ""
    @State private var selectedStatus = "All"
    @State private var editingApp: LCAppModel?
    @State private var refreshToken = UUID()

    private var allApps: [LCAppModel] {
        sharedModel.apps + sharedModel.hiddenApps
    }

    private var filteredApps: [LCAppModel] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allApps.filter { app in
            let status = app.appInfo.tinkerStatus ?? "Untested"
            let statusMatch = selectedStatus == "All" || status == selectedStatus
            guard statusMatch else { return false }
            guard !keyword.isEmpty else { return true }
            let name = app.displayName
            let bundleID = app.appInfo.bundleIdentifier() ?? ""
            let tags = app.appInfo.tinkerTags ?? ""
            return name.localizedCaseInsensitiveContains(keyword) ||
                bundleID.localizedCaseInsensitiveContains(keyword) ||
                tags.localizedCaseInsensitiveContains(keyword)
        }
        .sorted { ($0.appInfo.lastLaunched ?? .distantPast) > ($1.appInfo.lastLaunched ?? .distantPast) }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    TextField("搜索 App、Bundle ID 或标签", text: $searchText)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(statuses, id: \.self) { status in
                                Button {
                                    selectedStatus = status
                                } label: {
                                    Text(status)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedStatus == status ? Color.accentColor : Color(.systemGray6),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(selectedStatus == status ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    Text("\(filteredApps.count) 个 App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredApps.indices, id: \.self) { index in
                    let app = filteredApps[index]
                    Button {
                        editingApp = app
                    } label: {
                        TinkerAppRow(app: app, statusColor: statusColors[app.appInfo.tinkerStatus ?? "Untested"] ?? .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .id(refreshToken)
            .navigationTitle("折腾中心")
            .sheet(item: $editingApp) { app in
                TinkerAppEditor(app: app) {
                    refreshToken = UUID()
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct TinkerAppRow: View {
    let app: LCAppModel
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(app.displayName)
                    .font(.headline)
                Spacer()
                Text(app.appInfo.tinkerStatus ?? "Untested")
                    .font(.caption.bold())
                    .foregroundStyle(statusColor)
            }

            Text(app.appInfo.bundleIdentifier() ?? "Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("v\(app.version)")
                if let date = app.appInfo.lastLaunched {
                    Text("· \(Self.dateString(date))")
                }
                if app.appInfo.isHidden {
                    Text("· Hidden")
                }
                if app.appInfo.isShared {
                    Text("· Shared")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let tags = app.appInfo.tinkerTags, !tags.isEmpty {
                Text(tags)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct TinkerAppEditor: View {
    @Environment(\.dismiss) private var dismiss

    let app: LCAppModel
    let onSaved: () -> Void

    @State private var status: String
    @State private var notes: String
    @State private var tags: String

    init(app: LCAppModel, onSaved: @escaping () -> Void) {
        self.app = app
        self.onSaved = onSaved
        _status = State(initialValue: app.appInfo.tinkerStatus ?? "Untested")
        _notes = State(initialValue: app.appInfo.tinkerNotes ?? "")
        _tags = State(initialValue: app.appInfo.tinkerTags ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("App") {
                    Text(app.displayName)
                    Text(app.appInfo.bundleIdentifier() ?? "Unknown")
                        .foregroundStyle(.secondary)
                }

                Section("兼容状态") {
                    Picker("状态", selection: $status) {
                        ForEach(["Untested", "Works", "Partial", "Broken"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    TextField("标签，用逗号分隔", text: $tags)
                }

                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("启动 App") {
                        Task {
                            try? await app.runApp()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(app.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        app.appInfo.tinkerStatus = status
                        app.appInfo.tinkerNotes = notes
                        app.appInfo.tinkerTags = tags
                        app.objectWillChange.send()
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
    }
}
