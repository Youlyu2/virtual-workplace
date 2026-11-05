import Foundation
import Darwin

/// A lock is attached to the state path, so diagnostic instances can use a different file.
/// Keep the file in place on exit: unlinking it permits a second inode to bypass flock.
final class StateWriterLock {
    enum Failure: Error {
        case alreadyRunning(pid_t?)
    }

    private let descriptor: Int32

    init(stateURL: URL) throws {
        let url = stateURL.standardizedFileURL.resolvingSymlinksInPath()
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent(url.lastPathComponent + ".writer.lock")
        let fd = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            let owner = (try? String(contentsOf: lockURL, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            Darwin.close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw Failure.alreadyRunning(owner) }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
        ftruncate(fd, 0)
        let pid = String(getpid()) + "\n"
        pid.withCString { bytes in _ = Darwin.write(fd, bytes, strlen(bytes)) }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
