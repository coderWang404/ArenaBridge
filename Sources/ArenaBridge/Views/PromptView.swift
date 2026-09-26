import SwiftUI

struct PromptView: View {
    @EnvironmentObject var model: AppModel

    @State private var promptText = ""
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.openArena()
                } label: {
                    Label("打开 Arena", systemImage: "globe")
                }
                Button {
                    regenerate()
                } label: {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
                Button {
                    model.copyToClipboard(promptText)
                    showToast("已复制到剪贴板")
                } label: {
                    Label("复制到剪贴板", systemImage: "doc.on.doc")
                }
                Button {
                    let path = model.writePromptFile()
                    showToast("已保存 \(path)")
                } label: {
                    Label("保存到本地", systemImage: "square.and.arrow.down")
                }
                Button {
                    let keyPath = expandPath(model.config.serverKeyPath)
                    guard FileManager.default.fileExists(atPath: keyPath) else {
                        showToast("私钥文件不存在：\(keyPath)")
                        return
                    }
                    model.revealInFinder(keyPath)
                    showToast("已在访达中显示私钥，可直接拖给 agent 当附件（免转录）")
                } label: {
                    Label("显示私钥文件", systemImage: "key")
                }
                Spacer()
                Text("把这段发给 Arena 的 agent 模式即可接入本机")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            TextEditor(text: .constant(promptText))
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { regenerate() }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(text: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func regenerate() {
        promptText = model.generatePrompt()
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation { toast = nil }
        }
    }
}
