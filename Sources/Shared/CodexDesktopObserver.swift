import Foundation
import SQLite3
import Darwin

struct CodexObservedSession: Equatable {
    var id: String
    var title: String
    var runtimeType: String
    var activeFlags: [String]
    var turnStatus: String? = nil
    var pendingRequest: Bool = false
    var executionDetails: CodexExecutionDetails? = nil
    var startedAt: Date? = nil
    var hostID: String = "local"
    var hostName: String? = nil

    var identity: String { CodexThreadIdentity.key(threadID: id, hostID: hostID) }
}

struct CodexObservationResult: Equatable {
    var sessions: [CodexObservedSession]
    var isConnected: Bool
    var message: String
}

/// Read-only adapter for this installed Codex desktop's internal, local IPC.
/// It never starts/resumes turns, answers approvals, or edits Codex files.
/// The SQLite index discovers IDs; runtime status comes only from live IPC.
final class CodexDesktopObserver {
    var onUpdate: ((CodexObservationResult) -> Void)?
    private let control = CodexObserverControl()
    private let queue = DispatchQueue(label: "virtual-workplace.codex-observer", qos: .utility)

    init() {}
    deinit { stop() }

    func start() {
        guard let generation = control.begin() else { return }
        let control = self.control
        queue.async { [weak self] in
            let worker = CodexObserverWorker(control: control, generation: generation) { [weak self] result in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.control.matches(generation) else { return }
                    self.onUpdate?(result)
                }
            }
            worker.run()
        }
    }

    func stop() { control.end() }
}

private final class CodexObserverControl {
    private let lock = NSLock()
    private var running = false
    private var generation = 0
    func begin() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return nil }
        running = true; generation += 1
        return generation
    }
    func end() { lock.lock(); running = false; generation += 1; lock.unlock() }
    func matches(_ value: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running && value == generation
    }
}

private struct CodexObserverFailure: Error { var message: String }

private final class CodexObserverWorker {
    private struct Candidate {
        var id: String
        var title: String
        var rolloutPath: String?
        var hostID = "local"
        var hostName: String? = nil
        var key: String { CodexThreadIdentity.key(threadID: id, hostID: hostID) }
    }
    private struct Pending { var method: String; var threadID: String?; var deadline: TimeInterval }
    private struct Record {
        var session: CodexObservedSession
        var owner: String
        var revision: Int
        var lastTurnIndex: Int?
        var requests: [Bool]
        var streamDetails: CodexStreamDetails
    }
    private let control: CodexObserverControl
    private let generation: Int
    private let deliver: (CodexObservationResult) -> Void
    private let home: URL
    private let rolloutReader: CodexRolloutReader
    private var fd: Int32 = -1
    private var clientID: String?
    private var candidates: [Candidate] = []
    private var remoteCandidates: [CodexRemoteCandidate] = []
    private var localIndexAvailable = true
    private var pending: [String: Pending] = [:]
    private var owners: [String: String] = [:]
    private var records: [String: Record] = [:]
    private var detailSessionIDs: Set<String> = []
    private var discoveryQueue: [String] = []
    private var awaitingSnapshot: [String: TimeInterval] = [:]
    private var resyncAt: [String: TimeInterval] = [:]
    private var input = Data()
    private var output = Data()
    private var nextScan: TimeInterval = 0
    private var nextDiscovery: TimeInterval = 0
    private var nextDetailRead: TimeInterval = 0
    private var lastResult: CodexObservationResult?
    private let maximumFrame = 64 * 1024 * 1024
    private var isRunning: Bool { control.matches(generation) }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(control: CodexObserverControl, generation: Int, deliver: @escaping (CodexObservationResult) -> Void) {
        self.control = control; self.generation = generation; self.deliver = deliver
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            home = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            let realHome = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.path
            home = URL(fileURLWithPath: realHome).appendingPathComponent(".codex", isDirectory: true)
        }
        rolloutReader = CodexRolloutReader(home: home)
    }

    func run() {
        while isRunning {
            do {
                try connect()
                publish(connected: false, message: "正在连接 Codex…")
                try enqueueRequest("initialize", params: ["clientType": "virtual-workplace-observer"], version: 0)
                while isRunning { try pump() }
            } catch let error as CodexObserverFailure {
                publish(connected: false, message: error.message, clear: true)
            } catch {
                publish(connected: false, message: "Codex 连接失败，正在重试", clear: true)
            }
            disconnect()
            let retry = now + 2
            while isRunning && now < retry { Thread.sleep(forTimeInterval: 0.1) }
        }
        disconnect()
    }

    private func connect() throws {
        let path = home.appendingPathComponent("ipc/ipc.sock").path
        var address = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw CodexObserverFailure(message: "Codex IPC 路径过长")
        }
        var fileInfo = stat()
        guard lstat(path, &fileInfo) == 0, fileInfo.st_uid == getuid(),
              (fileInfo.st_mode & S_IFMT) == S_IFSOCK else {
            throw CodexObserverFailure(message: "未连接本机 Codex，请先打开 Codex 桌面应用")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CodexObserverFailure(message: "无法创建 Codex 本地连接") }
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else { throw CodexObserverFailure(message: "Codex 本地连接不可用，正在重试") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        nextScan = 0; nextDiscovery = 0; nextDetailRead = 0
    }

    private func disconnect() {
        if fd >= 0 {
            for (id, owner) in owners { try? follow(id, owner: owner, enabled: false) }
            try? flush()
            Darwin.close(fd)
        }
        fd = -1; clientID = nil
        pending.removeAll(); owners.removeAll(); records.removeAll(); candidates.removeAll()
        detailSessionIDs.removeAll()
        discoveryQueue.removeAll(); awaitingSnapshot.removeAll(); resyncAt.removeAll()
        input.removeAll(keepingCapacity: false); output.removeAll(keepingCapacity: false)
    }

    private func pump() throws {
        if clientID != nil && now >= nextScan {
            candidates = try readCandidates()
            let wanted = Set(candidates.map(\.key))
            rolloutReader.retain(threadIDs: Set(candidates.filter { $0.hostID == "local" }.map(\.id)))
            detailSessionIDs.formIntersection(wanted)
            for (id, owner) in owners where !wanted.contains(id) {
                try follow(id, owner: owner, enabled: false)
                owners.removeValue(forKey: id); records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
            }
            nextScan = now + 3
        }
        if clientID != nil && now >= nextDiscovery && discoveryQueue.isEmpty {
            discoveryQueue = candidates.map(\.key)
            nextDiscovery = now + 4
        }
        while clientID != nil && pending.count < 16 && !discoveryQueue.isEmpty {
            let id = discoveryQueue.removeFirst()
            if pending.values.contains(where: { $0.threadID == id }) { continue }
            if owners[id] == nil, let last = resyncAt[id], now - last < 10 { continue }
            guard let candidate = candidates.first(where: { $0.key == id }) else { continue }
            try enqueueRequest("thread-owner-discovery", params: ["hostId": candidate.hostID, "conversationId": candidate.id], version: 1, threadID: id)
        }
        for (requestID, request) in pending where now > request.deadline {
            pending.removeValue(forKey: requestID)
            if request.method == "initialize" { throw CodexObserverFailure(message: "Codex IPC 初始化超时，正在重试") }
            if let id = request.threadID, let owner = owners.removeValue(forKey: id) {
                try? follow(id, owner: owner, enabled: false)
                records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
            }
        }
        // One remote host may disconnect while the local desktop stays live.
        // Drop only the timed-out subscriptions; never keep their old active claim.
        for id in awaitingSnapshot.keys.filter({ now > (awaitingSnapshot[$0] ?? 0) }) {
            if let owner = owners.removeValue(forKey: id) { try? follow(id, owner: owner, enabled: false) }
            records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
        }
        try flush()
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN) | (output.isEmpty ? 0 : Int16(POLLOUT)), revents: 0)
        let status = Darwin.poll(&descriptor, 1, 100)
        guard status >= 0 || errno == EINTR else { throw CodexObserverFailure(message: "Codex 连接已断开，正在重试") }
        if descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
            throw CodexObserverFailure(message: "Codex 已断开，当前运行状态未知")
        }
        if descriptor.revents & Int16(POLLIN) != 0 { try readAvailable() }
        if descriptor.revents & Int16(POLLOUT) != 0 { try flush() }
        if clientID != nil && now >= nextDetailRead {
            for candidate in candidates {
                guard candidate.hostID == "local", var record = records[candidate.key], let path = candidate.rolloutPath else { continue }
                if record.session.runtimeType == "active" { detailSessionIDs.insert(candidate.key) }
                guard detailSessionIDs.contains(candidate.key) else { continue }
                // Runtime discovery and success semantics remain IPC-only.
                let observation = rolloutReader.read(threadID: candidate.id, at: path)
                record.session.executionDetails = observation?.details
                record.session.startedAt = observation?.startedAt
                records[candidate.key] = record
            }
            nextDetailRead = now + 1
        }
        if clientID != nil {
            let remoteHosts = Set(candidates.filter { $0.hostID != "local" }.map(\.hostID))
            let connectedHosts = Set(records.values.map { $0.session.hostID }).intersection(remoteHosts)
            var message: String
            if remoteHosts.isEmpty { message = "已连接 Codex · 本机状态实时更新" }
            else {
                let names = connectedHosts.sorted().prefix(2).map { host in
                    String((candidates.first { $0.hostID == host }?.hostName ?? "开发机").prefix(24))
                }
                let connected = names.isEmpty ? "开发机未连接" : names.joined(separator: "、")
                    + (connectedHosts.count > 2 ? "等\(connectedHosts.count)台" : "")
                message = "Codex 实时 · 本机 + \(connected)"
                    + (connectedHosts.count < remoteHosts.count ? " · 其余未连接" : "")
            }
            if !localIndexAvailable { message += " · 本机会话索引暂不可用" }
            publish(connected: true, message: message)
        }
    }

    private func enqueue(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(data.count).littleEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(data)
        guard output.count <= 4 * 1024 * 1024 else { throw CodexObserverFailure(message: "Codex IPC 写入阻塞，正在重新连接") }
    }

    private func enqueueRequest(_ method: String, params: [String: Any], version: Int, threadID: String? = nil) throws {
        let requestID = UUID().uuidString
        pending[requestID] = Pending(method: method, threadID: threadID, deadline: now + (method == "initialize" ? 4 : 2.5))
        try enqueue(["type": "request", "requestId": requestID, "sourceClientId": clientID ?? "initializing-client",
                     "version": version, "method": method, "params": params])
    }

    private func follow(_ id: String, owner: String, enabled: Bool) throws {
        guard let clientID else { return }
        // Records remain available while unsubscribing removed candidates.
        let candidate = candidates.first(where: { $0.key == id })
        let threadID = candidate?.id ?? records[id]?.session.id
        let hostID = candidate?.hostID ?? records[id]?.session.hostID
        guard let threadID, let hostID else { return }
        try enqueue(["type": "broadcast", "method": "thread-stream-following-changed", "sourceClientId": clientID,
                     "version": 1, "targetClientIds": [owner],
                     "params": ["conversationId": threadID, "hostId": hostID, "following": enabled]])
    }

    private func flush() throws {
        while !output.isEmpty {
            let written = output.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if written > 0 { output = Data(output.dropFirst(written)) }
            else if written < 0 && (errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR) { return }
            else { throw CodexObserverFailure(message: "Codex 连接写入失败，正在重试") }
        }
    }

    private func readAvailable() throws {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while isRunning {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count == 0 { throw CodexObserverFailure(message: "Codex 已断开，当前运行状态未知") }
            if count < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR { return }
                throw CodexObserverFailure(message: "Codex 连接读取失败，正在重试")
            }
            input.append(contentsOf: buffer.prefix(count))
            while input.count >= 4 {
                let size = Int(input.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) })
                guard size > 0 && size <= maximumFrame else {
                    throw CodexObserverFailure(message: "Codex 状态帧超出支持范围（最大 64 MiB），当前状态未知")
                }
                guard input.count >= size + 4 else { break }
                let start = input.startIndex
                let frame = input.subdata(in: (start + 4)..<(start + size + 4))
                input = Data(input.dropFirst(size + 4))
                // Discard full history immediately after reducing this message
                // to metadata. No conversation content is stored or logged.
                try autoreleasepool {
                    guard let message = try JSONSerialization.jsonObject(with: frame) as? [String: Any] else {
                        throw CodexObserverFailure(message: "Codex IPC 数据格式不受支持")
                    }
                    try handle(message)
                }
            }
        }
    }

    private func handle(_ message: [String: Any]) throws {
        let type = message["type"] as? String
        if type == "client-discovery-request", let requestID = message["requestId"] as? String {
            try enqueue(["type": "client-discovery-response", "requestId": requestID, "response": ["canHandle": false]])
            return
        }
        if type == "response", let requestID = message["requestId"] as? String, let request = pending.removeValue(forKey: requestID) {
            let success = message["resultType"] as? String == "success"
            if request.method == "initialize" {
                guard success, let result = message["result"] as? [String: Any], let id = result["clientId"] as? String else {
                    throw CodexObserverFailure(message: "当前 Codex 不支持此内部 IPC 适配")
                }
                clientID = id; return
            }
            guard let id = request.threadID else { return }
            if success, let owner = message["handledByClientId"] as? String {
                if owners[id] != owner {
                    if let old = owners[id] { try? follow(id, owner: old, enabled: false) }
                    records.removeValue(forKey: id)
                    owners[id] = owner; awaitingSnapshot[id] = now + 8
                    try follow(id, owner: owner, enabled: true)
                }
            } else if let owner = owners.removeValue(forKey: id) {
                try? follow(id, owner: owner, enabled: false)
                records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
            }
            return
        }
        guard type == "broadcast", let method = message["method"] as? String,
              let params = message["params"] as? [String: Any] else { return }
        if method == "client-status-changed", params["status"] as? String == "disconnected",
           let owner = params["clientId"] as? String {
            for id in owners.keys.filter({ owners[$0] == owner }) {
                owners.removeValue(forKey: id); records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
            }
            return
        }
        guard method == "thread-stream-state-changed", let hostID = params["hostId"] as? String,
              let threadID = params["conversationId"] as? String else { return }
        let id = CodexThreadIdentity.key(threadID: threadID, hostID: hostID)
        guard let owner = owners[id],
              message["sourceClientId"] as? String == owner else { return }
        guard (message["version"] as? NSNumber)?.intValue == 11,
              let change = params["change"] as? [String: Any], let revision = change["revision"] as? Int else {
            try dropSubscription(id, owner: owner)
            return
        }
        if change["type"] as? String == "snapshot", let state = change["conversationState"] as? [String: Any] {
            guard state["parentThreadId"] is NSNull || state["parentThreadId"] == nil else {
                try? follow(id, owner: owner, enabled: false)
                owners.removeValue(forKey: id); records.removeValue(forKey: id); awaitingSnapshot.removeValue(forKey: id)
                return
            }
            guard let runtime = state["threadRuntimeStatus"] as? [String: Any], let runtimeType = runtime["type"] as? String,
                  ["active", "idle", "notLoaded", "systemError"].contains(runtimeType) else {
                try dropSubscription(id, owner: owner)
                return
            }
            let title = (state["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = candidates.first(where: { $0.key == id })
            let indexedTitle = candidate?.title ?? "Codex 会话"
            let turns = state["turns"] as? [[String: Any]] ?? []
            let requests = requestFlags(state["requests"])
            let flags = runtime["activeFlags"] as? [String] ?? []
            let stream = CodexStreamDetails(state: state, at: Date())
            let session = CodexObservedSession(id: threadID, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? indexedTitle,
                runtimeType: runtimeType, activeFlags: flags, turnStatus: turns.last?["status"] as? String ?? stream.turnStatus,
                pendingRequest: requests.contains(true) || waitingFlag(flags),
                executionDetails: hostID == "local" ? nil : stream.details,
                startedAt: hostID == "local" ? nil : stream.startedAt, hostID: hostID, hostName: candidate?.hostName)
            records[id] = Record(session: session, owner: owner, revision: revision,
                                 lastTurnIndex: turns.isEmpty ? nil : turns.count - 1, requests: requests,
                                 streamDetails: stream)
            awaitingSnapshot.removeValue(forKey: id)
        } else if change["type"] as? String == "patches" {
            // Already-queued old patches can arrive after the resync request.
            // Wait for this thread's snapshot without disrupting other hosts.
            if records[id] == nil, awaitingSnapshot[id] != nil { return }
            guard var record = records[id], let base = change["baseRevision"] as? Int, base == record.revision,
                  let patches = change["patches"] as? [[String: Any]], revision >= base else {
                if let last = resyncAt[id], now - last < 10 {
                    try dropSubscription(id, owner: owner)
                    return
                }
                records.removeValue(forKey: id); resyncAt[id] = now
                try follow(id, owner: owner, enabled: false); try follow(id, owner: owner, enabled: true)
                awaitingSnapshot[id] = now + 8
                return
            }
            for patch in patches {
                do { try apply(patch, to: &record) }
                catch { try dropSubscription(id, owner: owner); return }
                record.streamDetails.apply(patch, at: Date())
            }
            record.session.turnStatus = record.streamDetails.turnStatus
            if hostID != "local" {
                record.session.executionDetails = record.streamDetails.details
                record.session.startedAt = record.streamDetails.startedAt
            }
            record.revision = revision
            record.session.pendingRequest = record.requests.contains(true) || waitingFlag(record.session.activeFlags)
            records[id] = record
            if record.streamDetails.needsSnapshot, now - (resyncAt[id] ?? -100) >= 10 {
                // A metadata shape change must clear details before requesting
                // a fresh snapshot. Other hosts and runtime subscriptions stay live.
                resyncAt[id] = now
                try follow(id, owner: owner, enabled: false)
                try follow(id, owner: owner, enabled: true)
                awaitingSnapshot[id] = now + 8
            }
        }
    }

    private func dropSubscription(_ id: String, owner: String) throws {
        try follow(id, owner: owner, enabled: false)
        owners.removeValue(forKey: id); records.removeValue(forKey: id)
        awaitingSnapshot.removeValue(forKey: id); resyncAt[id] = now
    }

    private func apply(_ patch: [String: Any], to record: inout Record) throws {
        guard let path = patch["path"] as? [Any], let root = path.first as? String else {
            throw CodexObserverFailure(message: "Codex 状态补丁结构已变化，当前运行状态未知")
        }
        let value = patch["value"], op = patch["op"] as? String
        if root == "threadRuntimeStatus" {
            if path.count == 1 {
                guard let runtime = value as? [String: Any], let type = runtime["type"] as? String,
                      ["active", "idle", "notLoaded", "systemError"].contains(type) else {
                    throw CodexObserverFailure(message: "Codex 运行状态不可识别，已停止显示旧状态")
                }
                record.session.runtimeType = type; record.session.activeFlags = runtime["activeFlags"] as? [String] ?? []
            } else if path.count == 2, path[1] as? String == "type" {
                guard let type = value as? String, ["active", "idle", "notLoaded", "systemError"].contains(type) else {
                    throw CodexObserverFailure(message: "Codex 运行状态不可识别，已停止显示旧状态")
                }
                record.session.runtimeType = type
            } else if path.count >= 2, path[1] as? String == "activeFlags" {
                if path.count == 2 { record.session.activeFlags = value as? [String] ?? [] }
                else if let index = path[2] as? Int {
                    if op == "remove", record.session.activeFlags.indices.contains(index) { record.session.activeFlags.remove(at: index) }
                    else if let flag = value as? String, index >= 0 && index <= record.session.activeFlags.count {
                        if op == "add" { record.session.activeFlags.insert(flag, at: index) }
                        else if record.session.activeFlags.indices.contains(index) { record.session.activeFlags[index] = flag }
                    }
                }
            }
        } else if root == "title", path.count == 1, let title = value as? String, !title.isEmpty {
            record.session.title = title
        } else if root == "turns" {
            if path.count == 1, let turns = value as? [[String: Any]] {
                record.lastTurnIndex = turns.isEmpty ? nil : turns.count - 1
                record.session.turnStatus = turns.last?["status"] as? String
            } else if path.count >= 2, let index = path[1] as? Int {
                if path.count == 2, op == "add" || op == "replace", let turn = value as? [String: Any], index >= (record.lastTurnIndex ?? -1) {
                    record.lastTurnIndex = index; record.session.turnStatus = turn["status"] as? String
                } else if path.count == 2, op == "remove", index == record.lastTurnIndex {
                    record.lastTurnIndex = nil; record.session.turnStatus = nil
                } else if path.count == 3, index == record.lastTurnIndex, path[2] as? String == "status" {
                    record.session.turnStatus = value as? String
                }
            }
        } else if root == "requests" {
            if path.count == 1 { record.requests = requestFlags(value) }
            else if path.count == 2, let index = path[1] as? Int {
                if op == "remove", record.requests.indices.contains(index) { record.requests.remove(at: index) }
                else if index >= 0 && index <= record.requests.count {
                    let known = isPendingRequest(value)
                    if op == "add" { record.requests.insert(known, at: index) }
                    else if record.requests.indices.contains(index) { record.requests[index] = known }
                }
            }
        }
    }

    private func waitingFlag(_ flags: [String]) -> Bool {
        flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
    }
    private func requestFlags(_ value: Any?) -> [Bool] { (value as? [Any] ?? []).map(isPendingRequest) }
    private func isPendingRequest(_ value: Any?) -> Bool {
        guard let request = value as? [String: Any] else { return false }
        let method = request["method"] as? String ?? (request["request"] as? [String: Any])?["method"] as? String
        return ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/permissions/requestApproval",
                "item/tool/requestUserInput", "mcpServer/elicitation/request"].contains(method ?? "")
    }

    private func readCandidates() throws -> [Candidate] {
        // The desktop owns the remote connection. Read its host/thread hints,
        // then subscribe through the same local IPC; no SSH, keys or remote agent.
        if let index = try? CodexRemoteIndex.read(at: home.appendingPathComponent(".codex-global-state.json")) {
            remoteCandidates = index
        }
        let local = try? readLocalCandidates()
        localIndexAvailable = local != nil
        let remote = remoteCandidates.map {
            Candidate(id: $0.threadID, title: "Codex 开发机会话", rolloutPath: nil,
                      hostID: $0.hostID, hostName: $0.hostName)
        }
        // Interleave recent local and remote candidates so a long unloaded
        // history on either host cannot delay discovering the other host's work.
        let localCandidates = local ?? []
        var result: [Candidate] = []
        for index in 0..<max(localCandidates.count, remote.count) {
            if localCandidates.indices.contains(index) { result.append(localCandidates[index]) }
            if remote.indices.contains(index) { result.append(remote[index]) }
        }
        return result
    }

    private func readLocalCandidates() throws -> [Candidate] {
        var db: OpaquePointer?
        let path = home.appendingPathComponent("state_5.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if db != nil { sqlite3_close(db) }
            throw CodexObserverFailure(message: "无法读取本机 Codex 会话索引")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)
        let sql = """
        SELECT id, COALESCE(NULLIF(name,''),NULLIF(title,''),'Codex 会话'), rollout_path FROM threads
        WHERE archived = 0 AND (agent_path IS NULL OR agent_path = '')
        AND source NOT LIKE '%subagent%' AND source NOT LIKE '%subAgent%'
        ORDER BY COALESCE(recency_at_ms,updated_at_ms,updated_at*1000) DESC LIMIT 100
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CodexObserverFailure(message: "当前 Codex 会话索引结构不受支持")
        }
        defer { sqlite3_finalize(statement) }
        var result: [Candidate] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let id = sqlite3_column_text(statement, 0), let title = sqlite3_column_text(statement, 1) {
                let path = sqlite3_column_text(statement, 2).map { String(cString: $0) }
                result.append(Candidate(id: String(cString: id), title: String(cString: title), rolloutPath: path))
            }
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CodexObserverFailure(message: "Codex 会话索引暂时繁忙，正在重试") }
        return result
    }

    private func publish(connected: Bool, message: String, clear: Bool = false) {
        let sessions = clear ? [] : candidates.compactMap { records[$0.key]?.session }
        let result = CodexObservationResult(sessions: sessions, isConnected: connected, message: message)
        if result != lastResult { lastResult = result; deliver(result) }
    }
}
