import AppKit

// 生成 ArenaBridge 架构图：docs/architecture_topology.png（全链路）+ docs/architecture_app.png（App 内部）
// 用法：swift make_arch.swift

func Y(_ y: CGFloat, _ h: CGFloat) -> CGFloat { h - y }

func drawText(_ s: String, at p: NSPoint, font: NSFont, color: NSColor, centered: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let size = (s as NSString).size(withAttributes: attrs)
    let x = centered ? p.x - size.width / 2 : p.x
    s.draw(at: NSPoint(x: x, y: p.y), withAttributes: attrs)
}

struct Palette {
    static let bg = NSColor(calibratedRed: 0.965, green: 0.973, blue: 0.984, alpha: 1)
    static let border = NSColor(calibratedRed: 0.79, green: 0.82, blue: 0.87, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1)
    static let sub = NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.52, alpha: 1)
    static let purple = NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.90, alpha: 1)
    static let green = NSColor(calibratedRed: 0.18, green: 0.66, blue: 0.38, alpha: 1)
    static let orange = NSColor(calibratedRed: 0.92, green: 0.55, blue: 0.13, alpha: 1)
    static let gray = NSColor(calibratedRed: 0.45, green: 0.48, blue: 0.53, alpha: 1)
    static let panelFill = NSColor(calibratedRed: 0.93, green: 0.955, blue: 0.985, alpha: 1)
}

func panel(_ image: NSImage, _ h: CGFloat, rect: NSRect, title: String?, lines: [String], stripe: NSColor, dashed: Bool = false) {
    image.lockFocus()
    let r = NSRect(x: rect.minX, y: Y(rect.minY + rect.height, h), width: rect.width, height: rect.height)
    let path = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
    NSColor.white.setFill()
    path.fill()
    stripe.withAlphaComponent(0.9).setStroke()
    path.lineWidth = 1.6
    path.stroke()
    // 左侧色条
    let stripeRect = NSRect(x: r.minX + 2, y: r.minY + 8, width: 4, height: r.height - 16)
    let stripePath = NSBezierPath(roundedRect: stripeRect, xRadius: 2, yRadius: 2)
    stripe.setFill()
    stripePath.fill()
    var y = r.maxY - 30
    if let title {
        drawText(title, at: NSPoint(x: r.minX + 18, y: y), font: .systemFont(ofSize: 15, weight: .semibold), color: Palette.ink)
        y -= 8
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: r.minX + 18, y: y))
        sep.line(to: NSPoint(x: r.maxX - 18, y: y))
        Palette.border.setStroke()
        sep.lineWidth = 0.8
        sep.stroke()
        y -= 22
    } else {
        y -= 12
    }
    for line in lines {
        drawText(line, at: NSPoint(x: r.minX + 18, y: y), font: .systemFont(ofSize: 12, weight: .regular), color: Palette.sub)
        y -= 19
    }
    image.unlockFocus()
}

// 去掉 setLineDash 影响

func arrowHead(_ p: NSPoint, _ angle: CGFloat, _ size: CGFloat, _ color: NSColor) {
    let path = NSBezierPath()
    path.move(to: p)
    path.line(to: NSPoint(x: p.x - size * cos(angle - .pi / 7), y: p.y - size * sin(angle - .pi / 7)))
    path.line(to: NSPoint(x: p.x - size * cos(angle + .pi / 7), y: p.y - size * sin(angle + .pi / 7)))
    path.close()
    color.setFill()
    path.fill()
}

func arrow(_ image: NSImage, _ h: CGFloat, from: NSPoint, to: NSPoint, color: NSColor, dashed: Bool = false, label: String? = nil, labelAt: NSPoint? = nil, bothEnds: Bool = false, labelCentered: Bool = true) {
    image.lockFocus()
    let a = NSPoint(x: from.x, y: Y(from.y, h))
    let b = NSPoint(x: to.x, y: Y(to.y, h))
    let line = NSBezierPath()
    line.move(to: a)
    line.line(to: b)
    if dashed {
        line.setLineDash([5, 4], count: 2, phase: 0)
    }
    color.setStroke()
    line.lineWidth = 1.8
    line.stroke()
    line.setLineDash([], count: 0, phase: 0)
    let angle = atan2(b.y - a.y, b.x - a.x)
    arrowHead(b, angle, 9, color)
    if bothEnds {
        arrowHead(a, angle + .pi, 9, color)
    }
    if let label, let lp = labelAt {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let bg = NSRect(x: lp.x - size.width / 2 - 6,
                        y: Y(lp.y, h) - 4,
                        width: size.width + 12,
                        height: 20)
        let bgp = NSBezierPath(roundedRect: bg, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.92).setFill()
        bgp.fill()
        drawText(label, at: NSPoint(x: lp.x, y: Y(lp.y, h)), font: .systemFont(ofSize: 11.5, weight: .medium), color: color, centered: true)
    }
    image.unlockFocus()
}

// MARK: - 图一：全链路拓扑

func drawTopology() -> NSImage {
    let W: CGFloat = 1600, H: CGFloat = 920
    let image = NSImage(size: NSSize(width: W, height: H))
    image.lockFocus()
    Palette.bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    image.unlockFocus()

    drawText("ArenaBridge 全链路：远端 Agent → 云服务器 → 反向隧道 → 本机 Mac", at: NSPoint(x: 50, y: Y(46, H)), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.ink)
    drawText("核心思路：App 在本机维护一条到云服务器的反向 SSH 隧道，arena agent 经服务器穿透回本机终端", at: NSPoint(x: 50, y: Y(74, H)), font: .systemFont(ofSize: 13, weight: .regular), color: Palette.sub)

    // 远端 agent
    panel(image, H, rect: NSRect(x: 50, y: 130, width: 330, height: 190),
          title: "远端 Arena Agent 沙箱",
          lines: ["Arena 网页里选中的 agent", "持钥：arena_server_key（私钥）", "来自 App 生成的「接入提示词」", "按提示词四步接入"],
          stripe: Palette.purple)

    // 云服务器
    panel(image, H, rect: NSRect(x: 620, y: 60, width: 400, height: 220),
          title: "云服务器（sshd:22，公网可达）",
          lines: ["authorized_keys：arena-server 公钥", "~/enter_mac.sh：进入 Mac 的命令封装", "~/arena-context/：上下文同步副本", "回环监听 127.0.0.1:2222", "（隧道只绑回环，公网扫不到）"],
          stripe: Palette.blue)

    // 本机 Mac 大框
    panel(image, H, rect: NSRect(x: 1180, y: 360, width: 370, height: 400),
          title: "本机 Mac（sshd:22）",
          lines: [],
          stripe: Palette.green)

    // Mac 内部三块
    panel(image, H, rect: NSRect(x: 1210, y: 425, width: 310, height: 120),
          title: "ArenaBridge.app",
          lines: ["TunnelManager：ssh -N -R 2222", "进程守护 + 断线 5 秒重连"],
          stripe: Palette.blue)
    panel(image, H, rect: NSRect(x: 1210, y: 565, width: 310, height: 110),
          title: "目录限制闸门",
          lines: ["arena_gate.sh + arena_jail.sb", "sandbox-exec 内核级沙箱"],
          stripe: Palette.orange)
    panel(image, H, rect: NSRect(x: 1210, y: 695, width: 310, height: 55),
          title: nil,
          lines: ["允许目录内才可读写（如 ~/localprojects）"],
          stripe: Palette.green)

    // 箭头
    arrow(image, H, from: NSPoint(x: 380, y: 225), to: NSPoint(x: 620, y: 170), color: Palette.purple,
          label: "① ssh -i arena_server_key 登录服务器", labelAt: NSPoint(x: 500, y: 168))
    arrow(image, H, from: NSPoint(x: 1210, y: 470), to: NSPoint(x: 1000, y: 285), color: Palette.blue,
          label: "② 反向隧道 ssh -N -R 2222:localhost:22", labelAt: NSPoint(x: 1085, y: 340), bothEnds: true)
    arrow(image, H, from: NSPoint(x: 1010, y: 200), to: NSPoint(x: 1210, y: 600), color: Palette.green,
          label: "③ ~/enter_mac.sh \"命令\"", labelAt: NSPoint(x: 1060, y: 470))
    arrow(image, H, from: NSPoint(x: 1185, y: 600), to: NSPoint(x: 1000, y: 225), color: Palette.gray, dashed: true,
          label: "④ 结果原路返回", labelAt: NSPoint(x: 1030, y: 255))
    arrow(image, H, from: NSPoint(x: 1365, y: 660), to: NSPoint(x: 1365, y: 700), color: Palette.orange,
          label: "⑤ 沙箱内执行", labelAt: NSPoint(x: 1365, y: 682))

    // 底部工具链说明
    panel(image, H, rect: NSRect(x: 50, y: 790, width: 1500, height: 100),
          title: "会话上下文工具链 ~/arena-context/（templates/arena-context/ 提供）",
          lines: ["refresh.sh → sessions_index.md（全部会话索引）+ transcript_current.md（最近会话转录）",
                  "export_session.py ← opencode.db 只读；可导出任意会话；文件随 ~/arena-context/ 同步到服务器，agent 读取后「继承对话」"],
          stripe: Palette.gray)
    return image
}

// MARK: - 图二：App 内部架构

func drawAppArchitecture() -> NSImage {
    let W: CGFloat = 1600, H: CGFloat = 1180
    let image = NSImage(size: NSSize(width: W, height: H))
    image.lockFocus()
    Palette.bg.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    image.unlockFocus()

    drawText("ArenaBridge App 内部架构（SwiftUI + Combine，零第三方依赖）", at: NSPoint(x: 50, y: Y(46, H)), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.ink)
    drawText("单向数据流：视图 → 服务层 → Shell 执行器 → 外部进程/文件；配置改动即时持久化", at: NSPoint(x: 50, y: Y(74, H)), font: .systemFont(ofSize: 13, weight: .regular), color: Palette.sub)

    // 视图层
    panel(image, H, rect: NSRect(x: 50, y: 100, width: 1500, height: 40), title: "① SwiftUI 视图层（ContentView 侧栏导航）", lines: [], stripe: Palette.blue)
    let views: [(String, String, CGFloat)] = [
        ("概览", "四项状态卡 + 一键操作", 90),
        ("隧道", "开关 / 日志 / 重连状态", 350),
        ("上下文", "会话索引 / 导出", 610),
        ("接入提示词", "生成 / 复制 / 保存", 870),
        ("设置", "服务器 / 密钥 / 目录限制", 1130)
    ]
    for (name, desc, x) in views {
        panel(image, H, rect: NSRect(x: x, y: 152, width: 240, height: 74),
              title: name,
              lines: [desc],
              stripe: Palette.blue)
    }

    // 服务层
    panel(image, H, rect: NSRect(x: 50, y: 300, width: 1500, height: 40), title: "② 状态与服务层（ObservableObject，经 @EnvironmentObject 注入）", lines: [], stripe: Palette.green)
    panel(image, H, rect: NSRect(x: 90, y: 352, width: 480, height: 190),
          title: "AppModel —— 状态中枢",
          lines: ["config：改动即写 UserDefaults", "refreshContext() 跑 refresh.sh", "chainTest() 全链路穿透测试", "generatePrompt() 接入提示词", "目录限制：生成闸门 + 改 authorized_keys"],
          stripe: Palette.green)
    panel(image, H, rect: NSRect(x: 610, y: 352, width: 420, height: 190),
          title: "TunnelManager —— 隧道守护",
          lines: ["Process 拉起 ssh -N -R", "readabilityHandler 实时收集日志", "terminationHandler → 5 秒自动重连", "退出 App 时 terminateNow()"],
          stripe: Palette.green)
    panel(image, H, rect: NSRect(x: 1070, y: 352, width: 300, height: 190),
          title: "StatusStore —— 巡检",
          lines: ["每 8 秒一次健康检查", "nc 探测 sshd / 服务器", "第 5 次做密钥登录实测", "驱动概览页四个状态卡"],
          stripe: Palette.green)
    panel(image, H, rect: NSRect(x: 1410, y: 352, width: 120, height: 190),
          title: "AppConfig",
          lines: ["Codable", "UserDefaults", "缺字段回落", "默认值"],
          stripe: Palette.gray)

    // Shell 层
    panel(image, H, rect: NSRect(x: 50, y: 620, width: 1500, height: 40), title: "③ Shell 执行器（Process + 超时 + 输出捕获，PATH 注入 homebrew/miniconda）", lines: [], stripe: Palette.orange)
    panel(image, H, rect: NSRect(x: 90, y: 672, width: 1440, height: 90),
          title: "外部进程",
          lines: ["ssh（隧道 / 测试 / 探测）      nc（端口探测）      expect（密码安装公钥）      osascript（提权开远程登录）      python3（导出会话）      sandbox-exec（目录沙箱）"],
          stripe: Palette.orange)

    // 文件层
    panel(image, H, rect: NSRect(x: 50, y: 830, width: 740, height: 180),
          title: "~/arena-context/（运行时工作区）",
          lines: ["refresh.sh → sessions_index.md + transcript_current.md",
                  "export_session.py → transcript_<id>.md（导出任意会话）",
                  "arena_prompt.md ← App「保存到 arena-context」",
                  "arena_gate.sh / allowed_dirs.conf / arena_jail.sb ← App 生成"],
          stripe: Palette.purple)
    panel(image, H, rect: NSRect(x: 830, y: 830, width: 720, height: 180),
          title: "外部世界",
          lines: ["云服务器 sshd:22 —— 隧道 + chainTest 穿透目标",
                  "本机 sshd:22 —— StatusStore 探测对象",
                  "~/.ssh/authorized_keys —— 目录限制闸门的挂载点",
                  "opencode.db（~/.local/share/）—— 会话数据源"],
          stripe: Palette.gray)

    // 层间箭头
    arrow(image, H, from: NSPoint(x: 800, y: 240), to: NSPoint(x: 800, y: 350), color: Palette.green,
          label: "@EnvironmentObject", labelAt: NSPoint(x: 800, y: 285))
    arrow(image, H, from: NSPoint(x: 800, y: 545), to: NSPoint(x: 800, y: 668), color: Palette.orange,
          label: "拉起 / 读输出", labelAt: NSPoint(x: 800, y: 600))
    arrow(image, H, from: NSPoint(x: 420, y: 670), to: NSPoint(x: 420, y: 825), color: Palette.purple, dashed: true,
          label: "读文件 / 执行脚本", labelAt: NSPoint(x: 420, y: 745))
    arrow(image, H, from: NSPoint(x: 1190, y: 825), to: NSPoint(x: 1190, y: 670), color: Palette.gray, dashed: true,
          label: "访问外部世界", labelAt: NSPoint(x: 1190, y: 748))
    arrow(image, H, from: NSPoint(x: 620, y: 352), to: NSPoint(x: 620, y: 246), color: Palette.gray, dashed: true,
          label: "config/日志 回传", labelAt: NSPoint(x: 620, y: 290), bothEnds: true)

    // 底部注释
    panel(image, H, rect: NSRect(x: 50, y: 1050, width: 1500, height: 100),
          title: "设计要点",
          lines: ["全部系统能力通过 Foundation/AppKit 标准 API 实现，零第三方依赖；macOS 14+",
                  "危险动作集中在 SettingsView：expect 装公钥（密码不落盘）、osascript 提权、ssh-keygen 轮换"],
          stripe: Palette.green)
    return image
}

func save(_ image: NSImage, _ path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("render failed: \(path)")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("written: \(path)")
}

save(drawTopology(), "docs/architecture_topology.png")
save(drawAppArchitecture(), "docs/architecture_app.png")
