import Darwin
import Foundation
import RocketCore

/// The `<name>.rocketpart` file. Every segment writes at its own offset with `pwrite`; no single-writer bottleneck.
/// `@unchecked Sendable`: the descriptor never changes after init, and `pwrite`/`fsync` are thread-safe
/// for the disjoint ranges segments write.
public final class PartFile: @unchecked Sendable {
    public let url: URL
    private let descriptor: Int32

    /// Opens (or creates) the file and preallocates `size` bytes when known.
    public init(url: URL, size: Int64?) throws {
        self.url = url
        descriptor = open(url.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw Self.error(errno, path: url.path) }
        // Large downloads should not evict useful page cache.
        _ = fcntl(descriptor, F_NOCACHE, 1)
        if let size { try preallocate(size) }
    }

    deinit {
        close(descriptor)
    }

    public func write(_ data: Data, at offset: Int64) throws {
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let result = pwrite(descriptor, buffer.baseAddress! + written, buffer.count - written, off_t(offset) + off_t(written))
                if result < 0 {
                    if errno == EINTR { continue }
                    throw Self.error(errno, path: url.path)
                }
                written += result
            }
        }
    }

    /// Flushes written bytes to stable storage. Checkpoints record offsets only after this returns.
    public func sync() throws {
        guard fsync(descriptor) == 0 else { throw Self.error(errno, path: url.path) }
    }

    /// Current length on disk.
    public func size() throws -> Int64 {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw Self.error(errno, path: url.path) }
        return Int64(status.st_size)
    }

    /// Records which download owns this part file, so leftovers can be matched after a crash.
    public func tag(downloadID: UUID) {
        let id = downloadID.uuidString
        _ = fsetxattr(descriptor, "io.github.neysidev.rocket.download-id", id, id.utf8.count, 0, 0)
    }

    /// Sets the final length (used when the size was unknown up front).
    public func truncate(to size: Int64) throws {
        guard ftruncate(descriptor, off_t(size)) == 0 else { throw Self.error(errno, path: url.path) }
    }

    private func preallocate(_ size: Int64) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw Self.error(errno, path: url.path) }
        let missing = size - Int64(status.st_size)
        guard missing > 0 else { return }
        var store = fstore_t(
            fst_flags: UInt32(F_ALLOCATEALL), fst_posmode: F_PEOFPOSMODE,
            fst_offset: 0, fst_length: off_t(missing), fst_bytesalloc: 0
        )
        // Best effort: some file systems do not support it; ENOSPC is a real answer though.
        if fcntl(descriptor, F_PREALLOCATE, &store) == -1, errno == ENOSPC { throw DownloadError.diskFull }
        try truncate(to: size)
    }

    static func error(_ code: Int32, path: String) -> DownloadError {
        switch code {
        case ENOSPC, EDQUOT: .diskFull
        case EACCES, EPERM, EROFS, ENOENT: .destinationNotWritable(path: path)
        default: .io(errno: code)
        }
    }
}
