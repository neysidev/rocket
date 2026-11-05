@testable import RocketUI
import Testing

@Suite struct FuzzyMatcherTests {
    @Test func matchesSubsequence() {
        let match = FuzzyMatcher.match(text: "ubuntu-22.04.iso", query: "u22")
        #expect(match != nil)
        #expect(match?.indices.isEmpty == false)
    }

    @Test func rejectsNonSubsequence() {
        #expect(FuzzyMatcher.match(text: "song.mp3", query: "xyz") == nil)
    }

    @Test func prefersEarlierCharacters() {
        let a = FuzzyMatcher.match(text: "archive.zip", query: "ar")?.score
        let b = FuzzyMatcher.match(text: "my-archive.zip", query: "ar")?.score
        #expect(a != nil && b != nil)
        #expect(a! >= b!)
    }

    @Test func bestMatchAcrossFields() {
        let result = FuzzyMatcher.bestMatch(
            in: [("report.pdf", 10), ("https://cdn.example.com/report.pdf", 4)],
            query: "cdn"
        )
        #expect(result?.field.contains("cdn") == true)
    }
}
