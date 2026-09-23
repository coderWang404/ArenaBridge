import SwiftUI

struct TunnelView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tunnel: TunnelManager
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            logConsole
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Toggle(isOn: Binding(
                    get: { tunnel.enabled },
                    set: { tunnel.setEnabled($0) }
                )) {
                    Text("反向隧道")
                }
                .toggleStyle(.switch)
                .controlSize(.large)

                HStack(spacing: 6) {
                    Circle()
                        .fill(tunnel.isRunning ? Color.green : (tunnel.enabled ? Color.orange : Color.secondary))
                        .frame(width: 8, height: 8)
                    Text(tunnel.isRunning ? "运行中" : (tunnel.enabled ? "重连中…" : "已停止"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let started = tunnel.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("已运行 \(durationText(since: started))")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button {
                    tunnel.clearLogs()
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
                .controlSize(.regular)
            }

            HStack(spacing: 24) {
                LabeledContent("服务器") {
                    Text("\(model.config.user)@\(model.config.host)")
                        .font(.system(.callout, design: .monospaced))
                }
                LabeledContent("端口映射") {
                    Text("127.0.0.1:\(model.config.remotePort) → 本机 \(model.config.localPort)")
                        .font(.system(.callout, design: .monospaced))
                }
                Spacer()
            }
        }
        .padding(20)
    }

    private var logConsole: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if tunnel.logs.isEmpty {
                        Text("暂无日志。启动隧道后，SSH 的输出会实时显示在这里。")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    }
                    ForEach(Array(tunnel.logs.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: tunnel.logs.count) { _, newValue in
                guard autoScroll, newValue > 0 else { return }
                withAnimation {
                    proxy.scrollTo(newValue - 1, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Toggle("自动滚动", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
            }
        }
    }

    private func durationText(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分 \(seconds % 60) 秒" }
        return "\(seconds / 3600) 时 \((seconds % 3600) / 60) 分"
    }
}
