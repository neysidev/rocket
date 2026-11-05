import Foundation
import RocketCore
import Testing

@Suite struct FileNameSanitizerTests {
    @Test(arguments: [
        ("ubuntu-24.04.iso", "ubuntu-24.04.iso"),
        ("../../.ssh/authorized_keys", "authorized_keys"),
        ("/etc/passwd", "passwd"),
        ("..\\..\\boot.ini", "boot.ini"),
        ("..", "download"),
        (".hidden", "hidden"),
        ("  spaced name.zip  ", "spaced name.zip"),
        ("a:b\u{0}c\nd.txt", "abcd.txt"),
        ("", "download"),
    ])
    func sanitizes(input: String, expected: String) {
        #expect(FileNameSanitizer.sanitize(input) == expected)
    }

    @Test func truncatesLongNamesKeepingExtension() {
        let name = FileNameSanitizer.sanitize(String(repeating: "é", count: 300) + ".iso")
        #expect(name.utf8.count <= 240)
        #expect(name.hasSuffix(".iso"))
    }

    @Test func containmentRejectsEscapes() {
        let folder = URL(filePath: "/tmp/downloads", directoryHint: .isDirectory)
        #expect(FileNameSanitizer.isInside(folder.appending(path: "a.iso"), folder: folder))
        #expect(!FileNameSanitizer.isInside(URL(filePath: "/tmp/downloads/../a.iso"), folder: folder))
        #expect(!FileNameSanitizer.isInside(folder.appending(path: "sub/a.iso"), folder: folder))
    }
}
