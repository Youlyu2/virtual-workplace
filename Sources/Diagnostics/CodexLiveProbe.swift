import Foundation

/// Uses the production observer and projection without creating NSApplication,
/// activating an app, opening a window, starting a task, or writing user state.
@main
enum CodexLiveProbe {
    private struct Options {
        var expectedThread: String?
        var expectedHost = "local"
        var hostWasSpecified = false
        var observeOnly = false
        var output: URL?
        var expectedDetails = false
        var expectedTool = false
    }

    private static let usage = "Usage: diagnose-codex-live.sh [--expect-thread UUID] [--expect-host HOST_ID] [--observe-only] [--expect-details|--expect-tool] [--output /absolute/project/build/snapshot.json]"

    private struct ProbeError: Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    static func main() {
        do { exit(try run(parseOptions())) }
        catch {
            let report: [String: Any] = ["success": false, "error": error.localizedDescription]
            writeReport(report)
            exit(2)
        }
    }

    private static func parseOptions() throws -> Options {
        var result = Options()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let flag = arguments.removeFirst()
            if flag == "--expect-details" { result.expectedDetails = true; continue }
            if flag == "--expect-tool" { result.expectedDetails = true; result.expectedTool = true; continue }
            if flag == "--observe-only" { result.observeOnly = true; continue }
            guard ["--expect-thread", "--expect-host", "--output"].contains(flag), !arguments.isEmpty else {
                throw ProbeError(message: usage)
            }
            let value = arguments.removeFirst()
            if flag == "--expect-thread" {
                guard UUID(uuidString: value) != nil else { throw ProbeError(message: "Expected a valid thread UUID.") }
                result.expectedThread = value.lowercased()
            } else if flag == "--expect-host" {
                guard !value.isEmpty, value.utf8.count <= 256,
                      value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw ProbeError(message: "Expected a nonempty host ID of at most 256 UTF-8 bytes without control characters.")
                }
                result.expectedHost = value
                result.hostWasSpecified = true
            } else {
                let output = URL(fileURLWithPath: value).standardizedFileURL.resolvingSymlinksInPath()
                let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WORKPLACE_PROBE_OUTPUT_ROOT"]
                               ?? FileManager.default.currentDirectoryPath + "/build")
                    .standardizedFileURL.resolvingSymlinksInPath()
                guard value.hasPrefix("/"), output.path.hasPrefix(root.path + "/"), output.pathExtension == "json" else {
                    throw ProbeError(message: "Snapshot output must be an absolute .json path inside this project's build directory.")
                }
                result.output = output
            }
        }
        guard !result.observeOnly || result.output == nil else {
            throw ProbeError(message: "--observe-only cannot write a scene snapshot; omit --output.")
        }
        return result
    }

    private static func run(_ options: Options) throws -> Int32 {
        if options.observeOnly { return runObserver(options) }
        let source = CodexLiveTaskSource()
        let expectedIdentity = options.expectedThread.map {
            CodexThreadIdentity.key(threadID: $0, hostID: options.expectedHost)
        }
        // Keep the Foundation main run loop alive so DispatchQueue.main can
        // deliver production observer callbacks even with no AppKit application.
        let keepAlive = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
        defer {
            source.stop()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            keepAlive.invalidate()
        }

        let started = ProcessInfo.processInfo.systemUptime
        var connectedSince: TimeInterval?
        var success = false
        source.start()
        while ProcessInfo.processInfo.systemUptime - started < 12 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let uptime = ProcessInfo.processInfo.systemUptime
            if source.isConnected {
                if connectedSince == nil { connectedSince = uptime }
                if let expected = expectedIdentity {
                    success = source.snapshot.tasks.contains {
                        $0.id == expected && ($0.status == .running || $0.status == .waiting)
                    }
                } else {
                    success = uptime - (connectedSince ?? uptime) >= 3
                    if options.hostWasSpecified {
                        success = success && source.snapshot.tasks.contains { ($0.hostID ?? "local") == options.expectedHost }
                    }
                }
                if options.expectedDetails {
                    success = success && source.snapshot.tasks.contains {
                        (expectedIdentity == nil || $0.id == expectedIdentity)
                            && ($0.hostID ?? "local") == options.expectedHost
                            && $0.executionDetails != nil
                            && (!options.expectedTool || $0.executionDetails?.phase == .tool)
                    }
                }
            } else {
                connectedSince = nil
            }
            if success { break }
        }

        source.tick(at: Date())
        let snapshot = source.snapshot
        if success, let output = options.output {
            try StateStore(url: output).write(snapshot)
        }
        let tasks: [[String: Any]] = snapshot.tasks.map {
            ["id": $0.id, "title": $0.title, "status": $0.status.rawValue,
             "hostID": $0.hostID ?? "local", "hostName": $0.hostName as Any? ?? NSNull(),
             "progress": $0.progress.map { $0 as Any } ?? NSNull(),
             "phase": $0.executionDetails?.phase.rawValue as Any? ?? NSNull(),
             "toolName": $0.executionDetails?.toolName as Any? ?? NSNull(),
             "hasLatestUpdate": $0.executionDetails?.latestUpdate != nil,
             "hasStartedAt": $0.startedAt != nil]
        }
        var report: [String: Any] = [
            "success": success,
            "source": snapshot.taskOrigin?.rawValue ?? "unknown",
            "connected": source.isConnected,
            "message": source.connectionMessage,
            "totalSessionCount": source.totalSessionCount,
            "tasks": tasks,
            "elapsedSeconds": (ProcessInfo.processInfo.systemUptime - started).rounded(),
            "observerStoppedOnExit": true
        ]
        if let expected = options.expectedThread { report["expectedThread"] = expected }
        report["expectedHost"] = options.expectedHost
        if success, let output = options.output { report["snapshotPath"] = output.path }
        if !success {
            report["failure"] = options.expectedThread == nil
                ? "No stable three-second connection within twelve seconds."
                : "Expected thread did not appear as running or waiting within twelve seconds."
        }
        writeReport(report)
        return success ? 0 : 1
    }

    /// Observes the exact same read-only IPC source but bypasses active-screen
    /// projection. An idle remote session can prove the remote read path without
    /// starting a turn or falsely presenting the session as running work.
    private static func runObserver(_ options: Options) -> Int32 {
        let observer = CodexDesktopObserver()
        var latest = CodexObservationResult(sessions: [], isConnected: false, message: "Observer starting")
        observer.onUpdate = { latest = $0 }
        let keepAlive = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in }
        defer {
            observer.stop()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            keepAlive.invalidate()
        }
        let started = ProcessInfo.processInfo.systemUptime
        var connectedSince: TimeInterval?
        var success = false
        observer.start()
        while ProcessInfo.processInfo.systemUptime - started < 20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let uptime = ProcessInfo.processInfo.systemUptime
            if latest.isConnected {
                if connectedSince == nil { connectedSince = uptime }
                let matching = latest.sessions.filter {
                    $0.hostID == options.expectedHost && (options.expectedThread == nil || $0.id == options.expectedThread)
                }
                success = options.expectedThread == nil
                    ? uptime - (connectedSince ?? uptime) >= 3 && !matching.isEmpty
                    : !matching.isEmpty
                if options.expectedDetails {
                    success = success && matching.contains {
                        $0.executionDetails != nil && (!options.expectedTool || $0.executionDetails?.phase == .tool)
                    }
                }
            } else { connectedSince = nil }
            if success { break }
        }
        let sessions: [[String: Any]] = latest.sessions.filter {
            $0.hostID == options.expectedHost && (options.expectedThread == nil || $0.id == options.expectedThread)
        }.map {
            ["id": $0.id, "identity": $0.identity, "hostID": $0.hostID,
             "hostName": $0.hostName as Any? ?? NSNull(),
             "runtimeType": $0.runtimeType, "turnStatus": $0.turnStatus as Any? ?? NSNull(),
             "hasDetails": $0.executionDetails != nil,
             "phase": $0.executionDetails?.phase.rawValue as Any? ?? NSNull(),
             "toolName": $0.executionDetails?.toolName as Any? ?? NSNull(),
             "hasLatestUpdate": $0.executionDetails?.latestUpdate != nil,
             "hasStartedAt": $0.startedAt != nil]
        }
        var report: [String: Any] = ["success": success, "observeOnly": true,
            "connected": latest.isConnected, "message": latest.message,
            "expectedHost": options.expectedHost, "observedSessionCount": latest.sessions.count,
            "sessions": sessions, "elapsedSeconds": (ProcessInfo.processInfo.systemUptime - started).rounded(),
            "observerStoppedOnExit": true]
        if let expected = options.expectedThread { report["expectedThread"] = expected }
        if !success { report["failure"] = "Expected host/thread observation or requested details did not arrive within twenty seconds." }
        writeReport(report)
        return success ? 0 : 1
    }

    private static func writeReport(_ report: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
