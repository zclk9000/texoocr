import Foundation

class Tokenizer {
    private let id2token: [Int: String]
    private let isWordLevel: Bool

    init(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let vocab = model["vocab"] as? [String: Int] else {
            throw NSError(domain: "Tokenizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid tokenizer.json format"])
        }

        // Detect tokenizer type
        let modelType = model["type"] as? String ?? ""
        self.isWordLevel = (modelType == "WordLevel")

        var mapping = [Int: String]()
        for (token, id) in vocab {
            mapping[id] = token
        }

        if let addedTokens = json["added_tokens"] as? [[String: Any]] {
            for tokenInfo in addedTokens {
                if let id = tokenInfo["id"] as? Int,
                   let content = tokenInfo["content"] as? String {
                    mapping[id] = content
                }
            }
        }

        self.id2token = mapping
    }

    func decode(tokenIds: [Int64]) -> String {
        var tokens: [String] = []

        for tokenId in tokenIds {
            guard let token = id2token[Int(tokenId)] else { continue }

            // Skip special tokens
            if token == "<pad>" || token == "<s>" || token == "</s>" ||
               token == "<unk>" || token == "<mask>" {
                continue
            }

            if isWordLevel {
                // WordLevel: each token is a complete symbol, join with spaces
                tokens.append(token)
            } else {
                // BPE: Ġ marks word boundary, replace with space
                tokens.append(token.replacingOccurrences(of: "\u{0120}", with: " "))
            }
        }

        if isWordLevel {
            return tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return tokens.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
