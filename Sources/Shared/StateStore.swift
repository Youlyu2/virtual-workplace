import Foundation
import Darwin

enum StateStoreError: Error, LocalizedError {
    case invalidSnapshot(String)
    var errorDescription: String? {
        switch self { case .invalidSnapshot(let reason): return "工位状态不可用：\(reason)" }
    }
}

struct StateStore {
    let url: URL
    private static let maximumFileSize = 131_072

    static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["WORKPLACE_STATE_PATH"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override)
        }
        // NSHomeDirectory may point inside legacyScreenSaver's sandbox container.
        let home: String
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            home = String(cString: directory)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/VirtualWorkplace/state.json")
    }

    init(url: URL = StateStore.defaultURL) { self.url = url }

    func write(_ snapshot: SceneSnapshot) throws {
        try validate(snapshot)
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maximumFileSize else { throw StateStoreError.invalidSnapshot("文件过大") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func read() throws -> SceneSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maximumFileSize else { throw StateStoreError.invalidSnapshot("文件过大") }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumFileSize else { throw StateStoreError.invalidSnapshot("文件过大") }
        let snapshot = try JSONDecoder().decode(SceneSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private func validate(_ snapshot: SceneSnapshot) throws {
        guard snapshot.schemaVersion == 1 else { throw StateStoreError.invalidSnapshot("版本不支持") }
        if let world = snapshot.world {
            do { try world.validate() }
            catch { throw StateStoreError.invalidSnapshot("屏幕背景设置不合法") }
        }
        if let notes = snapshot.pendingNotes {
            do { try PendingNote.validate(notes) }
            catch { throw StateStoreError.invalidSnapshot("待办内容不合法：\(error.localizedDescription)") }
        }
        if let timeline = snapshot.agentTimeline {
            do { try timeline.validate() }
            catch { throw StateStoreError.invalidSnapshot("Agent 姿态轨迹不合法：\(error.localizedDescription)") }
        }
        guard snapshot.tasks.count <= 6 else { throw StateStoreError.invalidSnapshot("会话数量超过六个") }
        guard Set(snapshot.tasks.map(\.id)).count == snapshot.tasks.count,
              Set(snapshot.tasks.map(\.slot)).count == snapshot.tasks.count else {
            throw StateStoreError.invalidSnapshot("会话或屏幕位置重复")
        }
        guard snapshot.tasks.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 128 && !$0.title.isEmpty && $0.title.count <= 160 && (0..<6).contains($0.slot) }) else {
            throw StateStoreError.invalidSnapshot("会话字段不合法")
        }
        guard snapshot.tasks.allSatisfy({ task in
            (task.progress.map { $0.isFinite && (0...1).contains($0) } ?? true)
                && (task.currentStep.map { $0.count <= 160 } ?? true)
                && (task.nextStep.map { $0.count <= 160 } ?? true)
        }) else { throw StateStoreError.invalidSnapshot("任务进度或步骤不合法") }
        guard snapshot.tasks.allSatisfy({ task in
            (task.hostID.map { !$0.isEmpty && $0.utf8.count <= 256 } ?? true)
                && (task.hostName.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 } ?? true)
        }) else { throw StateStoreError.invalidSnapshot("任务主机字段不合法") }
        guard snapshot.tasks.allSatisfy({ task in
            guard let details = task.executionDetails else { return true }
            return (details.latestUpdate.map { $0.count <= 320 } ?? true)
                && (details.toolName.map { $0.count <= 120 } ?? true)
                && (details.turnID.map { !$0.isEmpty && $0.utf8.count <= 128 } ?? true)
        }) else { throw StateStoreError.invalidSnapshot("任务详情字段不合法") }
        guard snapshot.completedToday.map({ (0...1_000_000).contains($0) }) ?? true else {
            throw StateStoreError.invalidSnapshot("今日完成数量不合法")
        }
        guard snapshot.sourceMessage.map({ $0.count <= 240 }) ?? true,
              snapshot.totalSessionCount.map({ (0...1_000_000).contains($0) }) ?? true else {
            throw StateStoreError.invalidSnapshot("任务来源字段不合法")
        }
        if let action = snapshot.action {
            guard !action.id.isEmpty, action.id.utf8.count <= 128 else {
                throw StateStoreError.invalidSnapshot("动作标识不合法")
            }
        }
        let dates = [snapshot.updatedAt, snapshot.lastWorkEndedAt, snapshot.summaryDay].compactMap { $0 }
            + snapshot.tasks.compactMap(\.startedAt)
            + snapshot.tasks.compactMap { $0.executionDetails?.updatedAt }
            + [snapshot.action?.startedAt].compactMap { $0 }
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite && $0.timeIntervalSince1970 >= 0 }) else {
            throw StateStoreError.invalidSnapshot("时间不合法")
        }
    }
}
