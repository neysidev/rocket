import Foundation

/// Subsequence fuzzy match with a simple score (Raycast-style). Case- and diacritic-insensitive.
enum FuzzyMatcher {
    struct Match: Sendable {
        let score: Int
        /// Indices in the original `text` string that matched the query.
        let indices: [Int]
    }

    /// Returns nil when `query` is empty or no subsequence match exists.
    static func match(text: String, query: String) -> Match? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let source = Array(text)
        let needle = Array(trimmed)
        var needleIndex = 0
        var score = 0
        var indices: [Int] = []
        var previousMatch: Int?

        for (index, character) in source.enumerated() {
            guard needleIndex < needle.count else { break }
            if character.fuzzyEquals(needle[needleIndex]) {
                var points = 1
                if index == 0 || isWordBoundary(before: source, at: index) { points += 4 }
                if let previousMatch, index == previousMatch + 1 { points += 3 }
                if index < 3 { points += 2 }
                score += points
                indices.append(index)
                previousMatch = index
                needleIndex += 1
            }
        }

        guard needleIndex == needle.count else { return nil }
        let coverage = Double(indices.count) / Double(max(source.count, 1))
        score += Int((1 - coverage) * 8)
        return Match(score: score, indices: indices)
    }

    /// Best field match among several haystacks (filename, URL, extension, …).
    static func bestMatch(in fields: [(String, Int)], query: String) -> (score: Int, indices: [Int], field: String)? {
        var best: (score: Int, indices: [Int], field: String)?
        for (field, weight) in fields {
            guard let match = match(text: field, query: query) else { continue }
            let weighted = match.score * weight
            if best == nil || weighted > best!.score {
                best = (weighted, match.indices, field)
            }
        }
        return best
    }

    private static func isWordBoundary(before source: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = source[index - 1]
        let current = source[index]
        return !prev.isLetter && !prev.isNumber && (current.isLetter || current.isNumber)
    }
}

private extension Character {
    func fuzzyEquals(_ other: Character) -> Bool {
        String(self).compare(String(other), options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
