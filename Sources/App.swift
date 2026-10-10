import SwiftUI
import AppKit

let accent = Color(red: 0.02, green: 0.39, blue: 1.0)
let ink = Color(red: 0.08, green: 0.13, blue: 0.23)
let muted = Color(red: 0.47, green: 0.53, blue: 0.63)
let hairline = Color(red: 0.90, green: 0.93, blue: 0.97)

struct ContentView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var filter = "全部任务"
    @State private var query = ""
    @State private var selectedID: String?
    @State private var removeTarget: DownloadItem?
    @State private var showSettings = false
    private let filters = [("全部任务", "square.stack"), ("下载中", "arrow.down.square"), ("已暂停", "pause.circle"), ("已完成", "checkmark.circle"), ("下载出错", "exclamationmark.circle"), ("BT / 磁力", "point.3.connected.trianglepath.dotted")]
    func matches(_ item: DownloadItem, _ category: String) -> Bool {
        switch category {
        case "下载中": return ["active", "waiting"].contains(item.status)
        case "已暂停": return item.status == "paused"
        case "已完成": return item.status == "complete"
        case "下载出错": return item.status == "error"
        case "BT / 磁力": return item.isBT
        default: return true
        }
    }
    var visibleItems: [DownloadItem] { engine.items.filter { matches($0, filter) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) } }
    var selectedItem: DownloadItem? { visibleItems.first { $0.id == selectedID } ?? visibleItems.first }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(hairline).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(hairline).frame(height: 1)
                listToolbar
                tableHeader
                ScrollView {
                    if visibleItems.isEmpty { emptyState }
                    else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleItems) { item in
                                DownloadRow(item: item, selected: selectedItem?.id == item.id, select: { selectedID = item.id }, toggle: { engine.toggle(item) }, reveal: { engine.reveal(item) }, remove: { removeTarget = item })
                            }
                        }
                    }
                }.padding(.horizontal, 24).frame(maxHeight: .infinity)
                Rectangle().fill(hairline).frame(height: 1)
                if let item = selectedItem { TaskDetailView(item: item, reveal: { engine.reveal(item) }) }
                else { idleDetails }
                footer
            }.background(.white)
        }
        .foregroundStyle(ink).preferredColorScheme(.light)
        .frame(minWidth: 1080, minHeight: 700)
        .onChange(of: engine.addedTaskRevision) { _, _ in filter = "全部任务"; query = "" }
        .onChange(of: filter) { _, _ in selectedID = nil }
        .sheet(isPresented: $showSettings) { settings }
        .sheet(isPresented: $engine.showLinkSwift) { LinkSwiftView(engine: engine) }
        .sheet(isPresented: $engine.showAdd) { AddDownloadView(engine: engine) }
        .alert("提示", isPresented: Binding(get: { engine.errorMessage != nil }, set: { if !$0 { engine.errorMessage = nil } })) { Button("知道了") { engine.errorMessage = nil } } message: { Text(engine.errorMessage ?? "") }
        .confirmationDialog("移除这个下载任务？", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
            Button("移除任务，保留已下载文件", role: .destructive) { if let item = removeTarget { engine.remove(item) }; removeTarget = nil }
            Button("取消", role: .cancel) { removeTarget = nil }
        } message: { Text("不会删除磁盘中的文件。") }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "bolt.fill").font(.system(size: 34, weight: .medium)).foregroundStyle(LinearGradient(colors: [.cyan, accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(alignment: .leading, spacing: 5) {
                    Text("疾风下载").font(.system(size: 22, weight: .bold))
                    Text("高效 · 简单 · 专注下载").font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(muted)
                }
            }.padding(.horizontal, 15).padding(.top, 32).padding(.bottom, 35)
            ForEach(filters, id: \.0) { name, icon in
                Button { filter = name } label: {
                    HStack(spacing: 13) {
                        Image(systemName: icon).font(.system(size: 18)).frame(width: 23)
                        Text(name).font(.system(size: 14, weight: filter == name ? .semibold : .regular))
                        Spacer(minLength: 0)
                        let count = engine.items.filter { matches($0, name) }.count
                        if count > 0 { Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit().padding(5).background((filter == name ? accent : muted).opacity(0.09), in: Capsule()) }
                    }.foregroundStyle(filter == name ? accent : ink.opacity(0.8)).padding(.horizontal, 14).frame(height: 47)
                        .background(filter == name ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).padding(.bottom, 5)
            }
            Rectangle().fill(hairline).frame(height: 1).padding(.horizontal, 13).padding(.vertical, 18)
            sidebarAction("导入种子", "doc.badge.plus") { engine.chooseTorrent() }
            sidebarAction("网盘推送", "link") { engine.showLinkSwift = true }
            sidebarAction("设置", "gearshape") { showSettings = true }
            Spacer(minLength: 20)
            HStack(spacing: 6) { Circle().fill(engine.ready ? Color.green : Color.orange).frame(width: 6, height: 6); Text(engine.connectionStatus).lineLimit(1) }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 15).padding(.bottom, 12)
            Text("疾风下载  v0.4.0").font(.system(size: 11)).foregroundStyle(muted).padding(.horizontal, 15).padding(.bottom, 22)
        }.padding(.horizontal, 12).frame(width: 204).background(Color(red: 0.967, green: 0.980, blue: 0.998))
    }
    func sidebarAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.system(size: 14)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15).frame(height: 44) }.buttonStyle(.plain).foregroundStyle(ink.opacity(0.8))
    }
    func newDownload() { engine.importedTorrent = nil; engine.showAdd = true }
    var topbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link").font(.system(size: 17)).foregroundStyle(muted)
                TextField("粘贴下载链接（HTTP / HTTPS / 磁力 / 视频网址）", text: $engine.newLink).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { newDownload() }
                if !engine.newLink.isEmpty { Button { engine.newLink = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(muted.opacity(0.7)) }.buttonStyle(.plain).help("清空链接") }
            }.padding(.horizontal, 14).frame(height: 44).background(.white, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(red: 0.82, green: 0.86, blue: 0.92)))
            Button(action: newDownload) { Text("新建下载").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 118, height: 44).background(accent, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain).keyboardShortcut("n", modifiers: .command)
        }.padding(.horizontal, 24).padding(.vertical, 24)
    }
    var listToolbar: some View {
        HStack(spacing: 10) {
            Text(filter).font(.system(size: 20, weight: .semibold))
            Text("\(visibleItems.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(accent).padding(.horizontal, 7).padding(.vertical, 3).background(accent.opacity(0.10), in: Capsule())
            Spacer()
            HStack(spacing: 6) { Image(systemName: "magnifyingglass"); TextField("搜索任务", text: $query).textFieldStyle(.plain) }.font(.system(size: 11)).foregroundStyle(muted).frame(width: 120)
            Button { engine.resumeAll() } label: { Label("全部开始", systemImage: "play") }.disabled(!engine.ready)
            Button { engine.pauseAll() } label: { Label("全部暂停", systemImage: "pause") }.disabled(!engine.ready)
            Menu {
                Button(engine.clearingCompleted ? "正在清除…" : "一键清除已完成记录") { engine.clearCompleted() }.disabled(!engine.ready || engine.clearingCompleted || !engine.items.contains { $0.status == "complete" })
                Button("打开下载目录") { engine.openDownloads() }
                Button("下载设置") { showSettings = true }
            } label: { Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)) }.menuStyle(.borderlessButton).fixedSize().help("更多操作 · 清除已完成记录")
        }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 26).frame(height: 65)
    }
    var tableHeader: some View {
        HStack(spacing: 12) {
            Text("文件名").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 44)
            Text("大小").frame(width: 70, alignment: .leading)
            Text("进度").frame(width: 148, alignment: .leading)
            Text("下载速度").frame(width: 85, alignment: .leading)
            Text("状态").frame(width: 94, alignment: .leading)
            Text("操作").frame(width: 66)
        }.font(.system(size: 11)).foregroundStyle(muted).padding(.horizontal, 14).frame(height: 38).overlay(alignment: .top) { hairline.frame(height: 1) }.padding(.horizontal, 24)
    }
    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "tray.and.arrow.down" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(accent.opacity(0.55))
            Text(query.isEmpty ? "这里还没有任务" : "没有匹配的任务").font(.system(size: 15, weight: .medium))
            Text(query.isEmpty ? "粘贴上方链接，开始你的下一次下载" : "尝试其他关键词或任务分类").font(.system(size: 12)).foregroundStyle(muted)
        }.frame(maxWidth: .infinity).frame(height: 220)
    }
    var idleDetails: some View {
        HStack { Image(systemName: "info.circle"); Text("选择任务，查看下载详情"); Spacer(); Text("HTTP / HTTPS · BitTorrent · 视频解析") }.font(.system(size: 11)).foregroundStyle(muted).padding(26)
    }
    var footer: some View {
        HStack(spacing: 7) {
            Circle().fill(engine.ready ? Color.green : Color.orange).frame(width: 5, height: 5)
            Text("仅本机控制").help(engine.bootstrapStatus)
            Spacer()
            Text("↓ " + formatBytes(engine.downloadSpeed) + "/s").foregroundStyle(accent)
            Text("↑ " + formatBytes(engine.uploadSpeed) + "/s").padding(.leading, 12)
        }.font(.system(size: 10)).foregroundStyle(muted).padding(.horizontal, 26).frame(height: 32).background(Color(red: 0.985, green: 0.990, blue: 1))
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("下载设置").font(.system(size: 22, weight: .semibold)); Spacer(); Button("完成") { showSettings = false } }
            Text("保存目录").font(.system(size: 13, weight: .semibold))
            HStack { Image(systemName: "folder").foregroundStyle(accent); Text(engine.downloadFolder).font(.system(size: 12)).lineLimit(2); Spacer(); Button("更改…") { engine.chooseFolder() } }
            Divider()
            Picker("BT 上传上限", selection: Binding(get: { engine.uploadLimit }, set: { engine.changeUploadLimit($0) })) { Text("256 KB/s").tag("256K"); Text("1 MB/s").tag("1M"); Text("5 MB/s").tag("5M"); Text("不限速").tag("0") }
            Text("下载不设速度上限，实际速度由网络和资源决定。").font(.system(size: 12)).foregroundStyle(muted)
            Text(engine.bootstrapStatus).font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("一键清除已完成记录（保留文件）") { engine.clearCompleted() }.disabled(engine.clearingCompleted || !engine.ready || !engine.items.contains { $0.status == "complete" })
        }.padding(28).frame(width: 520).background(.white).foregroundStyle(ink)
    }
}

struct FileGlyph: View {
    let item: DownloadItem
    var ext: String { URL(fileURLWithPath: item.name).pathExtension.lowercased() }
    var symbol: String {
        if item.isBT { return "shippingbox.fill" }
        if ["zip", "rar", "7z", "gz"].contains(ext) { return "doc.zipper" }
        if ext == "pdf" { return "doc.richtext.fill" }
        if ["mp3", "m4a", "flac", "wav", "opus"].contains(ext) { return "music.note" }
        if ["mp4", "mkv", "webm", "mov"].contains(ext) || item.source.hasPrefix("video:") { return "play.rectangle.fill" }
        if ["iso", "dmg"].contains(ext) { return "opticaldisc.fill" }
        return "doc.fill"
    }
    var color: Color { ["zip", "rar", "7z"].contains(ext) ? .orange : ext == "pdf" ? .red : item.isBT ? .purple : accent }
    var body: some View { Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(color).frame(width: 34, height: 40).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 6)) }
}

struct ThinProgress: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.88, green: 0.91, blue: 0.95))
                Capsule().fill(LinearGradient(colors: [Color(red: 0.18, green: 0.57, blue: 1), accent], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * min(1, max(0, value)))
            }
        }.frame(height: 6)
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let selected: Bool
    var select: () -> Void; var toggle: () -> Void; var reveal: () -> Void; var remove: () -> Void
    var color: Color { item.status == "error" ? .orange : item.status == "complete" ? .green : item.status == "paused" ? muted : accent }
    var canToggle: Bool { ["active", "waiting", "paused"].contains(item.status) || (item.status == "error" && item.source.hasPrefix("video:")) }
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) { FileGlyph(item: item); Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(item.name) }.frame(maxWidth: .infinity, alignment: .leading)
            Text(item.total == 0 ? "待获取" : formatBytes(item.total)).font(.system(size: 11)).foregroundStyle(muted).frame(width: 70, alignment: .leading)
            HStack(spacing: 8) { ThinProgress(value: item.progress); Text(item.total > 0 ? "\(Int(item.progress * 100))%" : "—").font(.system(size: 10)).monospacedDigit().foregroundStyle(muted).frame(width: 31, alignment: .trailing) }.frame(width: 148)
            Text(item.status == "active" ? formatBytes(item.speed) + "/s" : "—").font(.system(size: 11)).monospacedDigit().foregroundStyle(item.status == "active" ? accent : muted).frame(width: 85, alignment: .leading)
            HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(item.statusLabel).lineLimit(1) }.font(.system(size: 10)).frame(width: 94, alignment: .leading)
            HStack(spacing: 17) {
                if canToggle { Button(action: toggle) { Image(systemName: ["paused", "error"].contains(item.status) ? "play" : "pause") }.help(["paused", "error"].contains(item.status) ? "继续 / 重试" : "暂停") }
                else { Button(action: reveal) { Image(systemName: "folder") }.help("在 Finder 中显示") }
                Button(action: remove) { Image(systemName: "xmark") }.help("移除记录，保留文件")
            }.buttonStyle(.plain).font(.system(size: 13)).frame(width: 66)
        }.padding(.horizontal, 14).frame(height: 66).background(selected ? accent.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) { if !selected { hairline.frame(height: 1) } }
            .contentShape(Rectangle()).onTapGesture(perform: select)
            .accessibilityElement(children: .contain).accessibilityLabel(item.name + "，" + item.statusLabel)
            .contextMenu { Button("在 Finder 中显示", action: reveal); if canToggle { Button(["paused", "error"].contains(item.status) ? "继续 / 重试" : "暂停", action: toggle) }; Button("移除任务", action: remove) }
    }
}

struct TaskDetailView: View {
    let item: DownloadItem
    var reveal: () -> Void
    var remaining: String {
        if item.status == "complete" { return "已完成" }
        guard item.speed > 0, item.total > item.completed, item.status == "active" else { return "—" }
        let seconds = (item.total - item.completed) / item.speed
        if seconds >= 3600 { return "\(seconds / 3600) 小时 \((seconds % 3600) / 60) 分" }
        return "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("任务详情").font(.system(size: 14, weight: .semibold)); Spacer(); Text(item.isBT ? "BitTorrent" : item.source.hasPrefix("video:") ? "视频解析" : "HTTP / HTTPS").font(.system(size: 10)).foregroundStyle(muted) }
            HStack(spacing: 13) {
                FileGlyph(item: item).frame(width: 47, height: 49).background(hairline.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle).help(item.name)
                    HStack { ThinProgress(value: item.progress); Text(item.total > 0 ? "\(Int(item.progress * 100))%" : "—").font(.system(size: 11)).foregroundStyle(muted).frame(width: 37, alignment: .trailing) }
                }
            }
            HStack(spacing: 18) {
                detailStat("下载速度", item.status == "active" ? formatBytes(item.speed) + "/s" : "—", "arrow.down", blue: true)
                Divider().frame(height: 33)
                detailStat("剩余时间", remaining, "clock")
                Divider().frame(height: 33)
                detailStat("已下载 / 总大小", formatBytes(item.completed) + " / " + (item.total > 0 ? formatBytes(item.total) : "待获取"), "doc")
                Divider().frame(height: 33)
                detailStat(item.isBT ? "连接 / 种子" : "当前连接", item.source.hasPrefix("video:") ? "由解析器管理" : item.isBT ? "\(item.connections) / \(item.seeders)" : "\(item.connections)", "square.3.layers.3d")
            }.padding(.leading, 5)
            if !item.error.isEmpty { Text(item.error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2).textSelection(.enabled).help(item.error) }
            if item.isBT && item.total == 0 && item.status == "active" { Text(item.connections == 0 ? "正在通过 DHT / Tracker 寻找节点；也可以导入原始种子文件。" : "已连接节点，正在等待种子元数据。").font(.system(size: 11)).foregroundStyle(muted) }
            Rectangle().fill(hairline).frame(height: 1)
            HStack(spacing: 12) { Image(systemName: "folder"); Text("保存路径"); Text(item.directory.replacingOccurrences(of: NSHomeDirectory(), with: "~")).foregroundStyle(muted).lineLimit(1).truncationMode(.middle).help(item.directory); Spacer(minLength: 5); Button("打开文件夹", action: reveal).buttonStyle(.bordered).controlSize(.regular) }.font(.system(size: 11))
        }.padding(.horizontal, 26).padding(.vertical, 18)
    }
    func detailStat(_ title: String, _ value: String, _ icon: String, blue: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(blue ? accent : ink.opacity(0.8))
            VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(blue ? accent : ink).lineLimit(1).minimumScaleFactor(0.8); Text(title).font(.system(size: 10)).foregroundStyle(muted) }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LinkSwiftView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var copied = ""
    @State private var confirmReset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "link.circle.fill").font(.system(size: 28)).foregroundStyle(accent)
                Text("LinkSwift 网盘推送").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("完成") { engine.showLinkSwift = false }
            }
            Text("在浏览器登录夸克并选择文件，LinkSwift 获取直链，疾风接收下载任务。").font(.system(size: 12)).foregroundStyle(muted)
            Toggle("允许 LinkSwift 向本机新增下载", isOn: Binding(get: { engine.linkSwiftEnabled }, set: { enabled in Task { await engine.configureLinkSwift(["enabled": enabled, "directory": engine.downloadFolder]) } }))
                .toggleStyle(.switch).disabled(engine.linkSwiftBusy || !engine.ready)
            Text("仅监听 127.0.0.1。专用密钥只允许测试连接和新增下载，不开放任务删除、设置修改等控制功能。").font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("填写到 LinkSwift → 助手设置 → Aria2 服务设置").font(.system(size: 13, weight: .semibold))
            row("服务主机", "http://127.0.0.1", key: "host")
            row("服务端口", String(engine.linkSwiftInfo["port"] as? Int ?? 16801), key: "port")
            row("服务路径", "/jsonrpc", key: "path")
            row("服务密钥", "••••••••  本机专用密钥", key: "token")
            HStack { Text("存储路径").frame(width: 70, alignment: .leading); Text("在 LinkSwift 中留空，由疾风选择目录").foregroundStyle(muted); Spacer() }.font(.system(size: 12))
            Text("保存到：" + (engine.linkSwiftInfo["directory"] as? String ?? engine.downloadFolder)).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
            HStack {
                Button("打开 LinkSwift 官方项目") { NSWorkspace.shared.open(URL(string: "https://github.com/hmjz100/LinkSwift")!) }
                Spacer()
                Button("重置密钥") { confirmReset = true }.disabled(!engine.linkSwiftEnabled || engine.linkSwiftBusy)
            }
            Text("配置后先点「测试」，再在夸克页面选择文件 → 下载助手 → Aria2 推送。需安装油猴 / 脚本猫及 LinkSwift；登录在浏览器完成。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text("Cookie 和签名直链可能随断点信息保存在本机受限目录。不要分享密钥、Cookie、脚本调试日志或下载会话文件。当前含 Cookie 的推送只接受夸克 HTTPS 域名。").font(.system(size: 11)).foregroundStyle(muted).padding(12).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            if let error = engine.linkSwiftError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            HStack { Circle().fill(engine.linkSwiftEnabled ? .green : .gray).frame(width: 6, height: 6); Text(engine.linkSwiftEnabled ? "等待浏览器推送 · 已接收 \(engine.linkSwiftInfo["received"] as? Int ?? 0) 个任务" : "推送已关闭"); Spacer(); Text(copied).foregroundStyle(accent) }.font(.system(size: 11))
        }.padding(28).frame(width: 620).background(.white).foregroundStyle(ink)
        .task { await engine.loadLinkSwift() }
        .alert("重置 LinkSwift 密钥？", isPresented: $confirmReset) { Button("取消", role: .cancel) {}; Button("重置") { Task { await engine.configureLinkSwift(["rotate": true]) }; copied = "" } } message: { Text("旧密钥立即失效，需在浏览器脚本中重新填写。") }
    }
    func row(_ title: String, _ value: String, key: String) -> some View {
        HStack {
            Text(title).frame(width: 70, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(muted)
            Spacer()
            Button("复制") { engine.copyLinkSwift(key); copied = "已复制" + title }.disabled(!engine.linkSwiftEnabled)
        }.font(.system(size: 12))
    }
}

struct AddDownloadView: View {
    @ObservedObject var engine: DownloadEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack { Image(systemName: "plus.circle.fill").foregroundStyle(accent).font(.system(size: 24)); Text("新建下载").font(.system(size: 23, weight: .semibold)); Spacer(); Button { engine.showAdd = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).disabled(engine.isAdding) }
            Text("支持直链、磁力、种子和视频网址（YouTube / B站等）").font(.system(size: 12)).foregroundStyle(muted)
            if let torrent = engine.importedTorrent {
                HStack { Image(systemName: "doc.badge.gearshape").foregroundStyle(accent); Text(torrent.lastPathComponent).lineLimit(2); Spacer(); Button("移除") { engine.importedTorrent = nil } }.padding(20).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $engine.newLink).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden).padding(8)
                    if engine.newLink.isEmpty { Text("粘贴下载链接，每行一个…\nhttps://…\nmagnet:?xt=urn:btih:…").font(.system(size: 12)).foregroundStyle(muted.opacity(0.65)).padding(14).allowsHitTesting(false) }
                }.frame(height: 145).background(Color.gray.opacity(0.04), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.gray.opacity(0.15)))
            }
            if engine.importedTorrent == nil {
                Toggle("按视频网页解析（YouTube / B站 / 小红书 / 抖音等自动识别）", isOn: $engine.videoMode)
                    .font(.system(size: 12))
                HStack {
                    Toggle("仅音频 · MP3", isOn: $engine.videoAudioOnly)
                    Picker("优先画质", selection: $engine.videoQuality) {
                        Text("最佳").tag("best"); Text("4K").tag("2160"); Text("1080p").tag("1080"); Text("720p").tag("720"); Text("480p").tag("480")
                    }.disabled(engine.videoAudioOnly)
                }.font(.system(size: 12))
                Text("视频优先选择所选画质，没有匹配时使用可用版本，必要时合并为 MKV；音频转 MP3。首版仅支持单视频，不读取浏览器登录信息。其他站点请勾选视频解析；支持情况取决于 yt-dlp。")
                    .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            }
            HStack { Button { engine.chooseTorrent() } label: { Label("选择种子文件", systemImage: "doc.badge.plus") }; Spacer(); Text("BT v1 / 混合种子").font(.system(size: 10)).foregroundStyle(muted) }
            if let error = engine.addError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).font(.system(size: 12)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Color(red: 0.72, green: 0.24, blue: 0.17)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("add-download-error")
            }
            if let notice = engine.addNotice { Text(notice).font(.system(size: 11)).foregroundStyle(accent) }
            Divider()
            HStack { Image(systemName: "folder").foregroundStyle(accent); VStack(alignment: .leading, spacing: 4) { Text("保存到").font(.system(size: 10)).foregroundStyle(muted); Text(engine.downloadFolder).font(.system(size: 11)).lineLimit(2) }; Spacer(); Button("更改…") { engine.chooseFolder() } }
            Text("BT 使用系统 SOCKS5（如已启用）连接节点；DHT 发现始终直连，会公开本机网络 IP。新任务放在所选目录下的 BT 专属子目录。下载过程中会向其他节点上传。默认上传上限 1 MB/s，下载完成后停止做种。退出应用会停止下载，重开后可继续。纯 BT v2 种子暂不支持。").font(.system(size: 11)).foregroundStyle(muted).lineSpacing(4).padding(13).background(Color.gray.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            HStack { Text(engine.ready ? "● 下载引擎已就绪" : "正在启动引擎…").font(.system(size: 10)).foregroundStyle(engine.ready ? .green : .orange); Spacer(); Button("取消") { engine.showAdd = false }.disabled(engine.isAdding); Button { Task { if await engine.add() { engine.showAdd = false } } } label: { Text(engine.isAdding ? "正在添加…" : "开始下载").padding(.horizontal, 15).padding(.vertical, 4) }.buttonStyle(.borderedProminent).tint(accent).disabled(engine.isAdding || !engine.ready) }
        }.padding(29).frame(width: 580).background(.white).foregroundStyle(ink)
        .interactiveDismissDisabled(engine.isAdding)
        .onAppear { engine.addError = nil; engine.addNotice = nil }
        .onChange(of: engine.newLink) { _, _ in if !engine.isAdding { engine.addError = nil; engine.addNotice = nil } }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = DownloadEngine()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "疾风 · Surge Download"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.white
        window.contentView = NSHostingView(rootView: ContentView(engine: engine))
        window.minSize = NSSize(width: 1080, height: 730)
        window.center(); window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        let main = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于疾风下载", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出疾风下载", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let fileItem = NSMenuItem(); fileItem.title = "文件"; let fileMenu = NSMenu(title: "文件"); fileItem.submenu = fileMenu
        let newItem = fileMenu.addItem(withTitle: "新建下载", action: #selector(newDownload), keyEquivalent: "n"); newItem.target = self
        let torrentItem = fileMenu.addItem(withTitle: "导入种子…", action: #selector(importTorrent), keyEquivalent: "o"); torrentItem.target = self; main.addItem(fileItem)
        let editItem = NSMenuItem(); editItem.title = "编辑"; let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key) }; main.addItem(editItem)
        NSApp.mainMenu = main
        NSApp.activate(ignoringOtherApps: true)
        engine.start()
    }
    @objc func newDownload() { engine.importedTorrent = nil; engine.showAdd = true; window.makeKeyAndOrderFront(nil) }
    @objc func importTorrent() { engine.chooseTorrent() }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "疾风下载", .applicationVersion: "0.4.0 · Apple Silicon", .credits: NSAttributedString(string: "原生 SwiftUI · libtorrent BT / aria2 HTTP\n下载不限速；实际速度取决于网络与资源。\n引擎与第三方许可证随应用附带。")]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let torrent = urls.first(where: { $0.isFileURL && $0.pathExtension.lowercased() == "torrent" }) { engine.importedTorrent = torrent }
        else { engine.newLink = urls.map(\.absoluteString).joined(separator: "\n") }
        engine.showAdd = true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await engine.stop(); sender.reply(toApplicationShouldTerminate: true) }; return .terminateLater
    }
}

@main struct SurgeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
