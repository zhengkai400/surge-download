import Foundation
import Network

// A fresh aria2 1.37 table can ping a bootstrap router without expanding it before
// its first get_peers query. Fetch routing nodes with BEP 5 find_node first.
// Cache encoding matches aria2 release-1.37.0 DHTRoutingTableSerializer.cc (v3).
enum DHTBootstrap {
    indirect enum Value {
        case bytes(Data), dictionary([String: Value]), list([Value]), integer
        var dictionary: [String: Value]? { if case .dictionary(let d) = self { return d }; return nil }
        var bytes: Data? { if case .bytes(let d) = self { return d }; return nil }
    }
    struct Parser {
        var data: [UInt8]; var offset = 0
        mutating func parse(_ depth: Int = 0) throws -> Value {
            guard depth < 16, offset < data.count else { throw ParseError.invalid }
            let first = data[offset]
            if first == 100 || first == 108 {
                offset += 1; var map: [String: Value] = [:]; var list: [Value] = []
                while offset < data.count && data[offset] != 101 {
                    if first == 100 {
                        guard let key = try parse(depth + 1).bytes, let str = String(data: key, encoding: .utf8) else { throw ParseError.invalid }
                        map[str] = try parse(depth + 1)
                    } else { list.append(try parse(depth + 1)) }
                }
                guard offset < data.count else { throw ParseError.invalid }; offset += 1
                return first == 100 ? .dictionary(map) : .list(list)
            }
            if first == 105 {
                offset += 1
                while offset < data.count && data[offset] != 101 { offset += 1 }
                guard offset < data.count else { throw ParseError.invalid }; offset += 1; return .integer
            }
            var length = 0; var digits = 0
            while offset < data.count && (48...57).contains(data[offset]) {
                length = length * 10 + Int(data[offset] - 48); offset += 1; digits += 1
                guard digits <= 5, length <= 65535 else { throw ParseError.invalid }
            }
            guard digits > 0, offset < data.count, data[offset] == 58 else { throw ParseError.invalid }
            offset += 1
            guard length <= data.count - offset else { throw ParseError.invalid }
            let value = Data(data[offset..<(offset + length)]); offset += length; return .bytes(value)
        }
    }
    enum ParseError: Error { case invalid }
    final class Response: @unchecked Sendable {
        let lock = NSLock(); private var data: Data?
        func set(_ value: Data?) { lock.lock(); data = value; lock.unlock() }
        func get() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    }
    static func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }
    static func query(packet: Data, host: String = "dht.transmissionbt.com", port: UInt16 = 6881) -> Data? {
        let done = DispatchSemaphore(value: 0), response = Response()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: packet, completion: .contentProcessed { error in
                    if error != nil { done.signal(); return }
                    connection.receiveMessage { data, _, _, _ in response.set(data); done.signal() }
                })
            case .failed: done.signal()
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "surge.dht.bootstrap"))
        _ = done.wait(timeout: .now() + 4)
        connection.cancel(); return response.get()
    }
    // Do not treat duplicated bootstrap records or arbitrary file length as a healthy table.
    static func validCache(_ data: Data) -> Bool {
        guard data.count >= 56, Array(data.prefix(8)) == [0xa1,0xa2,2,0,0,0,0,3] else { return false }
        let count = data[48..<52].reduce(0) { ($0 << 8) | Int($1) }
        guard count >= 8, count <= 4096, data.count == 56 + count * 56 else { return false }
        var endpoints = Set<Data>(), identities = Set<Data>()
        for offset in stride(from: 56, to: data.count, by: 56) {
            guard data[offset] == 6 else { return false }
            endpoints.insert(data.subdata(in: offset+8..<offset+14))
            identities.insert(data.subdata(in: offset+32..<offset+52))
        }
        return endpoints.count == count && identities.count == count
    }
    static func prepare(cache: URL) -> String {
        let previous = try? Data(contentsOf: cache)
        if let previous, validCache(previous) { return "已加载 DHT 候选缓存（非资源连接数）" }
        let nodeID = (previous?.count ?? 0) >= 56 ? previous!.subdata(in: 24..<44) : random(20)
        let transaction = random(4)
        var packet = Data("d1:ad2:id20:".utf8); packet.append(nodeID)
        packet.append(Data("6:target20:".utf8)); packet.append(random(20))
        packet.append(Data("e1:q9:find_node1:t4:".utf8)); packet.append(transaction); packet.append(Data("1:y1:qe".utf8))
        guard let response = query(packet: packet), response.count <= 65535 else { return "DHT 引导未响应，将由引擎继续尝试" }
        var parser = Parser(data: Array(response))
        guard let message = try? parser.parse().dictionary,
              message["t"]?.bytes == transaction, message["y"]?.bytes == Data("r".utf8),
              let compact = message["r"]?.dictionary?["nodes"]?.bytes,
              compact.count > 0, compact.count % 26 == 0 else { return "DHT 引导响应未包含有效 IPv4 节点" }
        var records: [Data] = []; var endpoints = Set<Data>(); var identities = Set<Data>()
        for offset in stride(from: 0, to: min(compact.count, 26 * 64), by: 26) {
            let node = compact.subdata(in: offset..<(offset + 26)), bytes = Array(node)
            let a = bytes[20], b = bytes[21]
            guard a > 0, a < 224, a != 10, a != 127, !(a == 169 && b == 254), !(a == 172 && (16...31).contains(b)), !(a == 192 && b == 168), !(a == 100 && (64...127).contains(b)), bytes[24] != 0 || bytes[25] != 0 else { continue }
            let endpoint = node.subdata(in: 20..<26), identity = Data(node.prefix(20))
            guard !endpoints.contains(endpoint), !identities.contains(identity) else { continue }
            endpoints.insert(endpoint); identities.insert(identity)
            var record = Data([6]); record.append(Data(repeating: 0, count: 7))
            record.append(node.subdata(in: 20..<26)); record.append(Data(repeating: 0, count: 18))
            record.append(node.prefix(20)); record.append(Data(repeating: 0, count: 4)); records.append(record)
        }
        guard !records.isEmpty else { return "DHT 引导未返回可用公网节点" }
        var table = Data([0xa1, 0xa2, 0x02, 0, 0, 0, 0, 3])
        var time = UInt64(Date().timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: &time) { table.append(contentsOf: $0) }
        table.append(Data(repeating: 0, count: 8)); table.append(nodeID); table.append(Data(repeating: 0, count: 4))
        var count = UInt32(records.count).bigEndian
        withUnsafeBytes(of: &count) { table.append(contentsOf: $0) }
        table.append(Data(repeating: 0, count: 4)); records.forEach { table.append($0) }
        do {
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try table.write(to: cache, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
            return "DHT 候选 \(records.count) 个（已去重，连接待验证）"
        } catch { return "DHT 节点缓存写入失败，由引擎继续尝试" }
    }
}
