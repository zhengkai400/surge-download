import Foundation

struct LinkInputError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Normalize only magnet syntax; HTTP paths and signed query strings are left unchanged.
struct DownloadLinkInput {
    static func normalize(_ input: String) -> String {
        let outer = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}\u{200B}"))
        let trimmed = input.trimmingCharacters(in: outer)
        let ascii = String(String.UnicodeScalarView(trimmed.unicodeScalars.map { scalar in
            if (0xFF01...0xFF5E).contains(scalar.value) { return UnicodeScalar(scalar.value - 0xFEE0)! }
            return scalar
        }))
        guard ascii.lowercased().hasPrefix("magnet:") else { return trimmed }
        return "magnet:" + ascii.dropFirst(7)
    }

    static func validate(_ input: String) throws -> String {
        var normalized = normalize(input)
        if !normalized.lowercased().hasPrefix("magnet:") && (!(normalized.hasPrefix("http://") || normalized.hasPrefix("https://")) || normalized.rangeOfCharacter(from: .whitespacesAndNewlines) != nil) {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let matches = detector.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
                .filter { ["http", "https"].contains($0.url?.scheme?.lowercased() ?? "") }
            if matches.count == 1, let range = Range(matches[0].range, in: normalized) {
                normalized = String(normalized[range])
            } else if matches.count > 1 {
                throw LinkInputError(message: "每行请只放一个下载链接。")
            }
        }
        if normalized.hasPrefix("magnet:") {
            guard normalized.hasPrefix("magnet:?"), let components = URLComponents(string: normalized),
                  let query = components.queryItems else {
                throw LinkInputError(message: "磁力链接格式有误，应以 magnet:?xt=urn:btih: 开头。")
            }
            let topics = query.filter { $0.name.lowercased() == "xt" }.compactMap(\.value)
            let btih = topics.first { $0.lowercased().hasPrefix("urn:btih:") }
            guard let btih else {
                if topics.contains(where: { $0.lowercased().hasPrefix("urn:btmh:") }) {
                    throw LinkInputError(message: "这是纯 BT v2 磁力链接；当前版本支持 BT v1 或带 v1 哈希的混合种子。")
                }
                throw LinkInputError(message: "磁力链接缺少 xt=urn:btih: 信息，请复制完整链接。")
            }
            let hash = String(btih.dropFirst(9))
            let valid = hash.range(of: "^(?:[0-9A-Fa-f]{40}|[A-Za-z2-7]{32})$", options: .regularExpression) != nil
            guard valid else { throw LinkInputError(message: "磁力链接的 BT 哈希应为 40 位十六进制或 32 位 Base32；请检查链接是否复制完整。") }
            return normalized
        }
        guard let components = URLComponents(string: normalized), let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, components.url != nil else {
            throw LinkInputError(message: "请粘贴 HTTP / HTTPS 或 magnet 链接；种子文件请点击「选择种子文件」。")
        }
        return normalized
    }
}
