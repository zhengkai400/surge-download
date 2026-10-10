import Foundation
import AppKit

struct DownloadItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var status: String
    var total: Int64
    var completed: Int64
    var speed: Int64
    var uploadSpeed: Int64
    var connections: Int
    var seeders: Int
    var isBT: Bool
    var directory: String
    var paths: [String]
    var error: String
    var source: String
    var progress: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
    var statusLabel: String {
        switch status {
        case "active": return total == 0 && isBT ? "获取磁力元数据" : "正在下载"
        case "waiting": return "排队中"
        case "paused": return "已暂停"
        case "complete": return "已完成"
        case "error": return "下载出错"
        default: return status
        }
    }
    init(_ value: [String: Any]) {
        func int(_ key: String) -> Int64 { Int64(value[key] as? String ?? "0") ?? 0 }
        id = value["gid"] as? String ?? UUID().uuidString
        status = value["status"] as? String ?? "waiting"
        total = int("totalLength"); completed = int("completedLength")
        speed = int("downloadSpeed"); uploadSpeed = int("uploadSpeed")
        connections = Int(int("connections")); seeders = Int(int("numSeeders"))
        directory = value["dir"] as? String ?? ""
        let files = value["files"] as? [[String: Any]] ?? []
        paths = files.compactMap { $0["path"] as? String }.filter { !$0.isEmpty }
        let bt = value["bittorrent"] as? [String: Any]
        let info = bt?["info"] as? [String: Any]
        isBT = bt != nil || value["infoHash"] != nil
        source = ((files.first?["uris"] as? [[String: Any]])?.first?["uri"] as? String) ?? ""
        name = value["title"] as? String ?? info?["name"] as? String ?? ""
        if name.isEmpty { name = paths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "" }
        if name.isEmpty || name == "[METADATA]" { name = isBT ? "磁力任务 · 正在寻找节点" : (URL(string: source)?.lastPathComponent ?? "新下载") }
        if name.isEmpty { name = "新下载" }
        error = value["errorMessage"] as? String ?? ""
    }
}

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class DownloadEngine: ObservableObject {
    @Published var items: [DownloadItem] = []
    @Published var ready = false
    @Published var connectionStatus = "正在启动下载引擎…"
    @Published var errorMessage: String?
    @Published var downloadSpeed: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var downloadFolder: String
    @Published var bootstrapStatus = "正在准备 DHT"
    @Published var clearingCompleted = false
    @Published var showLinkSwift = false
    @Published var linkSwiftInfo: [String: Any] = [:]
    @Published var linkSwiftError: String?
    @Published var linkSwiftBusy = false
    private var linkSwiftReceived = -1
    @Published var showAdd = false
    @Published var newLink = ""
    @Published var videoMode = false
    @Published var videoAudioOnly = false
    @Published var videoQuality = "1080"
    @Published var addError: String?
    @Published var addNotice: String?
    @Published var isAdding = false
    @Published var addedTaskRevision = 0
    @Published var importedTorrent: URL?
    @Published var uploadLimit = "1M"
    private var process: Process?
    private var pollTask: Task<Void, Never>?
    private var token = UUID().uuidString + UUID().uuidString
    private var port = Int.random(in: 21000...48000)
    private var history: [String: DownloadItem] = [:]
    private var removed: Set<String> = []
    private var root: URL
    private var configuration: URL
    private var historyURL: URL
    private var started = false
    private var shuttingDown = false
    private var logHandle: FileHandle?
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 4
        c.connectionProxyDictionary = [:]
        return URLSession(configuration: c)
    }()

    init() {
        let home = ProcessInfo.processInfo.environment["SURGE_HOME"]
        root = home.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SurgeDownload", isDirectory: true)
        configuration = root.appendingPathComponent("engine.conf")
        historyURL = root.appendingPathComponent("history.json")
        downloadFolder = UserDefaults.standard.string(forKey: "downloadFolder") ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("疾风下载").path
        if let data = try? Data(contentsOf: historyURL), let saved = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            for item in saved { history[item.id] = item }
            items = saved
        }
    }

    func start() {
        guard !started else { return }; started = true
        connectionStatus = "正在启动 libtorrent + HTTP 引擎…"
        bootstrapStatus = "正在读取系统 SOCKS5 设置"
        launchEngine()
    }

    private func launchEngine() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let binary = Bundle.main.url(forResource: "aria2c", withExtension: nil, subdirectory: "engine")?.path ?? "/opt/homebrew/bin/aria2c"
            guard FileManager.default.isExecutableFile(atPath: binary) else { throw EngineError(message: "下载引擎缺失，请重新运行 build.sh 构建应用。") }
            let sessionFile = root.appendingPathComponent("downloads.session")
            if !FileManager.default.fileExists(atPath: sessionFile.path) { FileManager.default.createFile(atPath: sessionFile.path, contents: Data(), attributes: [.posixPermissions: 0o600]) }
            let config = """
            enable-rpc=true
            rpc-listen-all=false
            rpc-listen-port=\(port)
            rpc-secret=\(token)
            rpc-allow-origin-all=false
            rpc-max-request-size=24M
            no-netrc=true
            dir=\(downloadFolder)
            input-file=\(sessionFile.path)
            save-session=\(sessionFile.path)
            save-session-interval=5
            force-save=false
            pause=true
            continue=true
            allow-overwrite=false
            auto-file-renaming=true
            max-concurrent-downloads=5
            max-connection-per-server=8
            split=8
            min-split-size=4M
            max-overall-download-limit=0
            max-download-limit=0
            max-overall-upload-limit=1M
            seed-time=0
            enable-dht=false
            dht-entry-point=dht.transmissionbt.com:6881
            enable-dht6=false
            dht-file-path=\(root.appendingPathComponent("dht.dat").path)
            listen-port=49160-49200
            dht-listen-port=49201-49240
            bt-enable-lpd=false
            enable-peer-exchange=true
            bt-save-metadata=true
            rpc-save-upload-metadata=true
            check-integrity=true
            file-allocation=none
            disk-cache=16M
            max-tries=5
            retry-wait=3
            connect-timeout=20
            timeout=60
            max-download-result=1000
            keep-unfinished-download-result=true
            console-log-level=warn
            summary-interval=0
            stop-with-process=\(ProcessInfo.processInfo.processIdentifier)
            """
            try config.write(to: configuration, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
            let log = root.appendingPathComponent("engine.log")
            // A fresh log for this launch; unfinished tasks are kept separately.
            FileManager.default.createFile(atPath: log.path, contents: Data(), attributes: [.posixPermissions: 0o600])
            logHandle = try FileHandle(forWritingTo: log)
            let child = Process(); child.executableURL = Bundle.main.url(forResource: "surge-bt", withExtension: nil, subdirectory: "bt")
            guard let bridge = child.executableURL, FileManager.default.isExecutableFile(atPath: bridge.path) else { throw EngineError(message: "BT 引擎缺失，请重新构建应用。") }
            child.arguments = ["--conf-path=\(configuration.path)", "--aria2=\(binary)"]
            child.standardOutput = logHandle; child.standardError = logHandle
            child.currentDirectoryURL = root
            child.terminationHandler = { [weak self] p in
                Task { @MainActor in
                    guard let self, !self.shuttingDown else { return }
                    self.ready = false
                    self.connectionStatus = "引擎已停止（\(p.terminationStatus)）"
                    self.errorMessage = "下载引擎意外停止。请重新打开应用；诊断日志位于 \(log.path)"
                }
            }
            try child.run(); process = child
            pollTask = Task {
                for _ in 0..<35 {
                    if Task.isCancelled { return }
                    if (try? await rpc("aria2.getVersion")) != nil { ready = true; connectionStatus = "BT · libtorrent / HTTP · aria2"; break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                guard ready else { errorMessage = "引擎连接失败，请检查 engine.log 后重新打开应用。"; return }
                var failures = 0
                while !Task.isCancelled {
                    do { try await refresh(); failures = 0; connectionStatus = "BT · libtorrent / HTTP · aria2" }
                    catch { failures += 1; if failures >= 3 { connectionStatus = "连接中断，正在重试…" } }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        } catch { errorMessage = error.localizedDescription; connectionStatus = "启动失败"; started = false }
    }

    func rpc(_ method: String, _ params: [Any] = []) async throws -> Any {
        guard !shuttingDown || method == "aria2.saveSession" else { throw CancellationError() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": UUID().uuidString, "method": method, "params": ["token:\(token)"] + params])
        let (data, response) = try await session.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let error = json["error"] as? [String: Any] { throw EngineError(message: error["message"] as? String ?? "任务操作失败") }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EngineError(message: "下载引擎响应异常。") }
        return json["result"] ?? NSNull()
    }

    var linkSwiftEnabled: Bool { linkSwiftInfo["enabled"] as? Bool ?? false }
    func loadLinkSwift() async {
        do {
            let info = try await rpc("aria2.linkSwiftStatus") as? [String: Any] ?? [:]
            linkSwiftInfo = info
            let count = info["received"] as? Int ?? 0
            if linkSwiftReceived >= 0 && count > linkSwiftReceived { addedTaskRevision += 1 }
            linkSwiftReceived = count
        } catch { linkSwiftError = error.localizedDescription }
    }
    func configureLinkSwift(_ options: [String: Any]) async {
        guard !linkSwiftBusy else { return }
        linkSwiftBusy = true; linkSwiftError = nil
        defer { linkSwiftBusy = false }
        do { linkSwiftInfo = try await rpc("aria2.linkSwiftConfigure", [options]) as? [String: Any] ?? [:] }
        catch { linkSwiftError = error.localizedDescription }
    }
    func copyLinkSwift(_ key: String) {
        let value = key == "port" ? String(linkSwiftInfo["port"] as? Int ?? 16801) : (linkSwiftInfo[key] as? String ?? "")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
    func refresh() async throws {
        await loadLinkSwift()
        if let version = try await rpc("aria2.getVersion") as? [String: Any] {
            bootstrapStatus = (version["btNetwork"] as? String ?? "") + " · DHT 路由 " + (version["dhtNodes"] as? String ?? "0")
        }
        let active = try await rpc("aria2.tellActive") as? [[String: Any]] ?? []
        let waiting = try await rpc("aria2.tellWaiting", [0, 1000]) as? [[String: Any]] ?? []
        let stopped = try await rpc("aria2.tellStopped", [0, 1000]) as? [[String: Any]] ?? []
        let stats = try await rpc("aria2.getGlobalStat") as? [String: String] ?? [:]
        downloadSpeed = Int64(stats["downloadSpeed"] ?? "0") ?? 0
        uploadSpeed = Int64(stats["uploadSpeed"] ?? "0") ?? 0
        let all = active + waiting + stopped
        let live = all.filter { ($0["status"] as? String) != "removed" && ($0["followedBy"] as? [String] ?? []).isEmpty }
            .map(DownloadItem.init).filter { !removed.contains($0.id) }
        let liveIDs = Set(live.map(\.id))
        for item in live where item.status == "complete" || item.status == "error" { history[item.id] = item }
        let persisted = history.values.filter { !liveIDs.contains($0.id) && !removed.contains($0.id) }
        items = live + persisted.sorted { $0.name < $1.name }
        saveHistory()
    }
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(Array(history.values)) { try? data.write(to: historyURL, options: .atomic) }
    }
    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = "选择下载文件的保存位置"; p.prompt = "选择文件夹"
        if p.runModal() == .OK, let url = p.url { downloadFolder = url.path; UserDefaults.standard.set(downloadFolder, forKey: "downloadFolder"); Task { await configureLinkSwift(["directory": url.path]) } }
    }
    func chooseTorrent() {
        let p = NSOpenPanel(); p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.message = "选择 .torrent 种子文件"; p.prompt = "导入种子"
        if p.runModal() == .OK, let url = p.url {
            guard url.pathExtension.lowercased() == "torrent" else {
                if showAdd { addError = "请选择 .torrent 文件。" } else { errorMessage = "请选择 .torrent 文件。" }; return
            }
            addError = nil
            importedTorrent = url; showAdd = true
        }
    }
    func add() async -> Bool {
        guard !isAdding else { return false }
        isAdding = true; addError = nil; addNotice = nil
        defer { isAdding = false }
        do {
            guard ready else { throw EngineError(message: "下载引擎尚未就绪。") }
            guard !downloadFolder.contains("\n") && !downloadFolder.isEmpty else { throw EngineError(message: "请选择有效的保存目录。") }
            try FileManager.default.createDirectory(atPath: downloadFolder, withIntermediateDirectories: true)
            let options = ["dir": downloadFolder, "pause": "false", "pause-metadata": "false"]
            if let torrent = importedTorrent {
                let values = try torrent.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw EngineError(message: "此 Demo 支持 16 MB 以内的种子文件。") }
                let data = try Data(contentsOf: torrent)
                _ = try await rpc("aria2.addTorrent", [data.base64EncodedString(), [], options])
                addedTaskRevision += 1
            } else {
                let rawLinks = newLink.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                guard !rawLinks.isEmpty, rawLinks.count <= 100 else { throw EngineError(message: "请输入 1–100 个链接，每行一个。") }
                var links: [String] = []
                for (index, raw) in rawLinks.enumerated() {
                    do { links.append(try DownloadLinkInput.validate(raw)) }
                    catch { throw EngineError(message: "第 \(index + 1) 行：\(error.localizedDescription)") }
                }
                if links != rawLinks {
                    newLink = links.joined(separator: "\n")
                    addNotice = "已提取分享链接或规范化磁力链接格式。"
                }
                var failures: [(link: String, reason: String)] = []
                for link in links {
                    do {
                        let host = URL(string: link)?.host?.lowercased() ?? ""
                        let autoVideo = host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv" || host == "vimeo.com" || host.hasSuffix(".vimeo.com") || host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com") || host == "xhslink.com" || host == "xhslink.cn" || host == "douyin.com" || host.hasSuffix(".douyin.com")
                        if videoMode || autoVideo {
                            _ = try await rpc("aria2.addVideo", [link, ["dir": downloadFolder, "mode": videoAudioOnly ? "audio" : "video", "quality": videoQuality]])
                        } else { _ = try await rpc("aria2.addUri", [[link], options]) }
                        addedTaskRevision += 1
                    }
                    catch { failures.append((link, error.localizedDescription)) }
                }
                if !failures.isEmpty {
                    newLink = failures.map(\.link).joined(separator: "\n")
                    _ = try? await rpc("aria2.saveSession"); try? await refresh()
                    let details = failures.prefix(3).enumerated().map { "\($0.offset + 1). \($0.element.reason)" }.joined(separator: "\n")
                    throw EngineError(message: "\(links.count - failures.count) 个任务已添加，\(failures.count) 个添加失败；失败链接已保留。\n\(details)")
                }
            }
            _ = try? await rpc("aria2.saveSession")
            try? await refresh(); newLink = ""; importedTorrent = nil; return true
        } catch { addError = error.localizedDescription; return false }
    }
    func toggle(_ item: DownloadItem) {
        Task {
            do { _ = try await rpc(["paused", "error"].contains(item.status) ? "aria2.unpause" : "aria2.pause", [item.id]); _ = try? await rpc("aria2.saveSession"); try await refresh() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func pauseAll() { Task { do { _ = try await rpc("aria2.pauseAll"); _ = try? await rpc("aria2.saveSession"); try await refresh() } catch { errorMessage = error.localizedDescription } } }
    func resumeAll() { Task { do { _ = try await rpc("aria2.unpauseAll"); try await refresh() } catch { errorMessage = error.localizedDescription } } }
    func remove(_ item: DownloadItem) {
        Task {
            do {
                if ["active", "waiting", "paused"].contains(item.status) { _ = try await rpc("aria2.forceRemove", [item.id]) }
                _ = try? await rpc("aria2.removeDownloadResult", [item.id])
                removed.insert(item.id); history.removeValue(forKey: item.id); items.removeAll { $0.id == item.id }
                saveHistory(); _ = try? await rpc("aria2.saveSession")
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func clearCompleted() {
        guard !clearingCompleted else { return }
        let targets = items.filter { $0.status == "complete" }
        guard !targets.isEmpty else { return }
        clearingCompleted = true
        Task {
            defer { clearingCompleted = false }
            do {
                // Enumerate stopped records before distinguishing engine vs. history-only entries.
                var liveIDs = Set<String>()
                var offset = 0
                while true {
                    let page = try await rpc("aria2.tellStopped", [offset, 1000]) as? [[String: Any]] ?? []
                    for entry in page where entry["status"] as? String == "complete" {
                        if let id = entry["gid"] as? String { liveIDs.insert(id) }
                    }
                    if page.count < 1000 { break }
                    offset += page.count
                }
                var failures = 0
                for item in targets {
                    do {
                        if liveIDs.contains(item.id) { _ = try await rpc("aria2.removeDownloadResult", [item.id]) }
                        removed.insert(item.id)
                        history.removeValue(forKey: item.id)
                        items.removeAll { $0.id == item.id }
                    } catch { failures += 1 }
                }
                saveHistory()
                _ = try? await rpc("aria2.saveSession")
                if failures > 0 { errorMessage = "有 \(failures) 条记录清除失败，已保留，可稍后重试。" }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func reveal(_ item: DownloadItem) {
        let urls = item.paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if let first = urls.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: item.directory)) }
    }
    func openDownloads() { try? FileManager.default.createDirectory(atPath: downloadFolder, withIntermediateDirectories: true); NSWorkspace.shared.open(URL(fileURLWithPath: downloadFolder)) }
    func changeUploadLimit(_ value: String) { Task { do { _ = try await rpc("aria2.changeGlobalOption", [["max-overall-upload-limit": value]]); uploadLimit = value } catch { errorMessage = error.localizedDescription } } }
    func stop() async {
        shuttingDown = true; pollTask?.cancel(); saveHistory()
        _ = try? await rpc("aria2.saveSession")
        if let p = process, p.isRunning { p.terminate() }
        try? logHandle?.close(); try? FileManager.default.removeItem(at: configuration)
    }
}

func formatBytes(_ value: Int64) -> String {
    if value < 1024 { return "\(value) B" }
    let units = ["KB", "MB", "GB", "TB"]
    var v = Double(value) / 1024; var i = 0
    while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
    return String(format: "%.1f %@", v, units[i])
}
