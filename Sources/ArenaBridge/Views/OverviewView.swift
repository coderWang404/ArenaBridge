import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tunnel: TunnelManager
    @EnvironmentObject var status: StatusStore

    @State private var testing = false
    @State private var testResult = ""
    @State private var showTestSheet = false
    @State private var toast: String?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    StatusCard(
                        title: "本机 sshd",
                        subtitle: "macOS 远程登录",
                        icon: "desktopcomputer",
                        state: status.localSSHD,
                        detail: "监听 127.0.0.1:22"
                    )
                    StatusCard(
                        title: "反向隧道",
                        subtitle: "Mac → \(model.config.host)",
                        icon: "arrow.left.arrow.right",
                        state: tunnelState,
                        detail: tunnelDetail
                    )
                    StatusCard(
                        title: "云服务器",
                        subtitle: "\(model.config.user)@\(model.config.host)",
                        icon: "cloud",
                        state: status.serverReachable,
                        detail: "密钥登录 " + (status.keyAuth == .ok ? "正常" : "异常")
                    )
                    StatusCard(
                        title: "会话上下文",
                        subtitle: "转录 / 索引 / 导出工具",
                        icon: "doc.text",
                        state: status.contextReady,
                        detail: "~/arena-context"
                    )
                }
                actions
                logPreview
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showTestSheet) {
            TestResultSheet(text: testResult) {
                model.copyToClipboard(testResult)
                showToast("测试结果已复制")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("本地终端桥接")
                    .font(.system(size: 26, weight: .semibold))
                Text("Arena Agent → 阿里云服务器 → 反向隧道 → 本机 Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(status.overall.color).frame(width: 9, height: 9)
                Text(status.overallText)
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(status.overall.color.opacity(0.12), in: Capsule())
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                tunnel.setEnabled(!tunnel.enabled)
            } label: {
                Label(tunnel.enabled ? "停止隧道" : "启动隧道", systemImage: tunnel.enabled ? "stop.fill" : "play.fill")
                    .frame(minWidth: 88)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                runTest()
            } label: {
                if testing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("测试中…")
                    }
                } else {
                    Label("全链路测试", systemImage: "checkmark.seal")
                }
            }
            .controlSize(.large)
            .disabled(testing)

            Button {
                model.copyToClipboard(model.generatePrompt())
                showToast("接入提示词已复制，去 Arena 粘贴")
            } label: {
                Label("复制接入提示词", systemImage: "paperplane")
            }
            .controlSize(.large)

            Button {
                model.refreshContext { message in showToast(message) }
            } label: {
                Label("刷新上下文", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)

            Spacer()
        }
    }

    private var logPreview: some View {
        Card {
            HStack {
                Label("隧道日志", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Text("\(tunnel.logs.count) 条")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Divider().padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 3) {
                if tunnel.logs.isEmpty {
                    Text("暂无日志")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(tunnel.logs.suffix(8).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var tunnelState: CheckState {
        if tunnel.isRunning { return .ok }
        return tunnel.enabled ? .checking : .fail
    }

    private var tunnelDetail: String {
        let state = tunnel.isRunning ? "运行中" : (tunnel.enabled ? "重连中…" : "已停止")
        return "\(state) · 服务器 127.0.0.1:\(model.config.remotePort)"
    }

    private func runTest() {
        testing = true
        model.chainTest { result in
            testing = false
            testResult = result
            showTestSheet = true
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { toast = nil }
        }
    }
}
