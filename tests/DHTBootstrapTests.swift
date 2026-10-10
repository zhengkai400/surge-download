import Foundation
@main struct DHTBootstrapTests {
    static func main() throws {
        let path = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : FileManager.default.temporaryDirectory.appendingPathComponent("surge-swift-dht-\(UUID().uuidString)").appendingPathComponent("dht.dat")
        print(DHTBootstrap.prepare(cache: path))
        if let data = try? Data(contentsOf: path) { print("Cache bytes: \(data.count)"); precondition(data.count >= 112); precondition(Array(data.prefix(8)) == [0xa1,0xa2,2,0,0,0,0,3]) }
        else { throw NSError(domain: "BootstrapNetwork", code: 1, userInfo: [NSLocalizedDescriptionKey: "No network response; bootstrap not verified"]) }
    }
}
