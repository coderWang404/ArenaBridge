import SwiftUI

struct SessionRow: Identifiable {
    let id: String
    let time: String
    let directory: String
    let title: String
}

struct ContextView: View {
    @EnvironmentObject var model: AppModel

    @State private var sessions: [SessionRow] = []
    @State private var selection: String?
    @State private var statusText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    loadSessions()
                } label: {
                    Label("刷新列表", systemImage: "arrow.clockwise")
                }
                Button {
                    model.refreshContext { statusText = $0 }
                } label: {
                    Label("重新导出会话", systemImage: "square.and.arrow.down")
                }
                Button {
                    model.openInFinder(model.contextDir)
                } label: {
                    Label("打开文件夹", systemImage: "folder")
                }
                Spacer()
                Button {
                    if let selection { exportSession(selection) }
                } label: {
                    Label("导出选中会话", systemImage: "doc.badge.plus")
                }
                .disabled(selection == nil)
            }
            .padding(20)

            Divider()

            if sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.tertiary)
                    Text("未找到会话索引")
                        .foregroundStyle(.secondary)
                    Text("点击「重新导出会话」生成 ~/arena-context/sessions_index.md")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(sessions, selection: $selection) { session in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 10) {
                            Text(session.id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(session.time)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(session.directory)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(session.id)
                }
                .listStyle(.inset)
            }

            if !statusText.isEmpty {
                Divider()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadSessions() }
    }

    private func loadSessions() {
        let path = model.contextDir + "/sessions_index.md"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            sessions = []
            return
        }
        var rows: [SessionRow] = []
        for line in text.split(separator: "\n") {
            let parts = line.components(separatedBy: " | ")
            guard parts.count >= 4, parts[0].hasPrefix("ses_") else { continue }
            rows.append(SessionRow(
                id: parts[0],
                time: parts[1],
                directory: parts[2],
                title: parts[3]
            ))
        }
        sessions = rows
    }

    private func exportSession(_ id: String) {
        let script = model.contextDir + "/export_session.py"
        statusText = "正在导出 \(id)…"
        Shell.runAsync("/usr/bin/env", ["python3", script, id], timeout: 120) { result in
            if result.ok {
                let out = model.contextDir + "/transcript_\(id).md"
                try? result.output.write(toFile: out, atomically: true, encoding: .utf8)
                model.revealInFinder(out)
                statusText = "已导出：\(out)"
            } else {
                statusText = "导出失败：\(result.output)"
            }
        }
    }
}
