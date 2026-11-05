import Foundation
import CryptoKit
import Darwin

/// IPC addresses a thread by both host and conversation ID. Keep the existing
/// local identity, and give remote threads a stable identity small enough for
/// the scene snapshot even when a remote host has a long identifier.
enum CodexThreadIdentity {
    static func key(threadID: String, hostID: String) -> String {
        guard hostID != "local" else { return threadID }
        let hostDigest = digest(hostID).prefix(24)
        let thread = UUID(uuidString: threadID) == nil ? digest(threadID) : threadID
        return "remote:\(hostDigest):\(thread)"
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CodexRemoteCandidate: Equatable {
    var threadID: String
    var hostID: String
    var hostName: String?
}

enum CodexRemoteIndexError: Error {
    case unavailable
    case invalidFile
    case tooLarge
    case invalidFormat
}

/// Only remote thread-to-host hints and display names are selected from the
/// desktop's metadata. SSH endpoints, identities and other settings are never
/// inspected. These hints discover IDs; live IPC must still prove runtime state.
enum CodexRemoteIndex {
    static let maximumBytes = 8 * 1024 * 1024
    private static let maximumHosts = 8
    private static let maximumPerHost = 32
    private static let maximumCandidates = 128

    static func read(at url: URL) throws -> [CodexRemoteCandidate] {
        // Opening nonblocking also avoids waiting on a FIFO before fstat can
        // reject it. O_NOFOLLOW and fstat validate the same descriptor we read.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw CodexRemoteIndexError.unavailable }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_size >= 0 else {
            throw CodexRemoteIndexError.invalidFile
        }
        guard info.st_size <= maximumBytes else { throw CodexRemoteIndexError.tooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw CodexRemoteIndexError.unavailable
            }
            guard data.count + count <= maximumBytes else { throw CodexRemoteIndexError.tooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> [CodexRemoteCandidate] {
        guard data.count <= maximumBytes else { throw CodexRemoteIndexError.tooLarge }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexRemoteIndexError.invalidFormat
        }
        guard root["thread-project-membership-host-ids"] == nil
                || root["thread-project-membership-host-ids"] is [String: Any],
              root["codex-managed-remote-connections"] == nil
                || root["codex-managed-remote-connections"] is [[String: Any]] else {
            throw CodexRemoteIndexError.invalidFormat
        }

        var names: [String: String] = [:]
        for connection in root["codex-managed-remote-connections"] as? [[String: Any]] ?? [] {
            guard let hostID = connection["hostId"] as? String, validHost(hostID),
                  let name = connection["displayName"] as? String else { continue }
            let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0)
            })).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { names[hostID] = String(cleaned.prefix(80)) }
        }

        var byHost: [String: [CodexRemoteCandidate]] = [:]
        var seen: [String: Set<String>] = [:]
        for (threadID, value) in root["thread-project-membership-host-ids"] as? [String: Any] ?? [:] {
            guard UUID(uuidString: threadID) != nil,
                  let hostID = value as? String, validHost(hostID) else { continue }
            let normalized = threadID.lowercased()
            guard seen[hostID, default: []].insert(normalized).inserted else { continue }
            byHost[hostID, default: []].append(CodexRemoteCandidate(threadID: normalized,
                hostID: hostID, hostName: names[hostID]))
        }
        for host in byHost.keys {
            byHost[host] = Array(byHost[host]!.sorted { $0.threadID > $1.threadID }.prefix(maximumPerHost))
        }
        let hosts = Array(byHost.keys.sorted {
            // Prefer a configured/named connection, then hosts with newer IDs.
            if (names[$0] != nil) != (names[$1] != nil) { return names[$0] != nil }
            let first = byHost[$0]?.first?.threadID ?? ""
            let second = byHost[$1]?.first?.threadID ?? ""
            return first == second ? $0 < $1 : first > second
        }.prefix(maximumHosts))

        // Round robin prevents one busy machine from hiding all other machines.
        var candidates: [CodexRemoteCandidate] = []
        for offset in 0..<maximumPerHost {
            for host in hosts where (byHost[host]?.count ?? 0) > offset {
                guard candidates.count < maximumCandidates else { break }
                candidates.append(byHost[host]![offset])
            }
            if candidates.count >= maximumCandidates { break }
        }
        return candidates.sorted {
            $0.threadID == $1.threadID ? $0.hostID < $1.hostID : $0.threadID > $1.threadID
        }
    }

    private static func validHost(_ value: String) -> Bool {
        !value.isEmpty && value != "local" && value.utf8.count <= 256
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
