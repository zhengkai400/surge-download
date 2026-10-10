import Foundation
@main struct LinkInputTests {
    static func main() throws {
        if CommandLine.arguments.count == 2 { print(try DownloadLinkInput.validate(CommandLine.arguments[1])); return }
        let hash = String(repeating: "a", count: 40)
        let good = "magnet:?xt=urn:btih:" + hash
        func equal(_ raw: String, _ expected: String) throws {
            let result = try DownloadLinkInput.validate(raw)
            precondition(result == expected, "Unexpected normalization")
        }
        func reject(_ raw: String) {
            do { _ = try DownloadLinkInput.validate(raw); fatalError("Expected rejection") } catch {}
        }
        try equal("分享示例视频 https://xhslink.cn/o/EXAMPLE 把内容复制好，打开【小红书】即可看到笔记详情。", "https://xhslink.cn/o/EXAMPLE")
        try equal(good, good)
        try equal("magnet:？xt=urn:btih:" + hash, good)
        try equal("　ｍａｇｎｅｔ：？ｘｔ＝ｕｒｎ：ｂｔｉｈ：" + hash + "　", good)
        try equal("MAGNET:?xt=urn:btih:" + hash, good)
        try equal("\u{FEFF}" + good + "\u{200B}", good)
        try equal(good + "＆dn＝测试.zip", good + "&dn=测试.zip")
        try equal("https://example.com/a%2Fb?sig=AbC%3D&name=中文？", "https://example.com/a%2Fb?sig=AbC%3D&name=中文？")
        try equal("magnet:?xt=urn:btih:" + String(repeating: "A", count: 32), "magnet:?xt=urn:btih:" + String(repeating: "A", count: 32))
        reject(""); reject("not a URL"); reject("magnet:xt=urn:btih:" + hash)
        reject("magnet:?xt=urn:btih:1234"); reject("magnet:?xt=urn:btih:" + String(repeating: "z", count: 40))
        reject("magnet:?xt=urn:btmh:1220abcd"); reject("file:///tmp/test"); reject("https://")
        print("PASS: 16 link normalization/validation cases, including fullwidth question mark, invalid hashes, BT v2 rejection and signed HTTP preservation")
    }
}
