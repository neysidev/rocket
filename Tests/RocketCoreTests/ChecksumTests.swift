import RocketCore
import Testing

@Suite struct ChecksumTests {
    @Test func parsesPrefixedAndBareHex() {
        #expect(Checksum("sha256:" + String(repeating: "AB", count: 32)) == Checksum(algorithm: .sha256, value: String(repeating: "ab", count: 32)))
        #expect(Checksum("SHA-1=" + String(repeating: "0", count: 40))?.algorithm == .sha1)
        #expect(Checksum(String(repeating: "f", count: 32))?.algorithm == .md5)
        #expect(Checksum(String(repeating: "f", count: 64))?.algorithm == .sha256)
    }

    @Test func rejectsMalformed() {
        #expect(Checksum("") == nil)
        #expect(Checksum("sha256:abc") == nil)              // wrong length
        #expect(Checksum("md5:" + String(repeating: "z", count: 32)) == nil) // not hex
        #expect(Checksum("crc32:deadbeef") == nil)
        #expect(Checksum(String(repeating: "a", count: 33)) == nil)
    }
}
