import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview
    case tunnel
    case prompt
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .tunnel: return "隧道"
        case .prompt: return "接入提示词"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge"
        case .tunnel: return "arrow.left.arrow.right"
        case .prompt: return "paperplane"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var status: StatusStore
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
            .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView()
                case .tunnel: TunnelView()
                case .prompt: PromptView()
                case .settings: SettingsView()
                }
            }
            .navigationTitle((selection ?? .overview).title)
            .toolbar {
                ToolbarItem(placement: .status) {
                    HStack(spacing: 6) {
                        Circle().fill(status.overall.color).frame(width: 7, height: 7)
                        Text(status.overallText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle().fill(status.overall.color).frame(width: 8, height: 8)
                Text(status.overallText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let checked = status.lastChecked {
                    Text(checked, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }
}
