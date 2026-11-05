import Foundation
import Darwin

/// Preferences are independent of task snapshots, so changing task sources or
/// quitting the companion app cannot erase a display's chosen background.
struct WorldSettingsStore {
    let url: URL
    static var defaultURL: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/VirtualWorkplace/world-settings.json")
    }

    init(url: URL = WorldSettingsStore.defaultURL) { self.url = url }

    static func validate(_ world: SceneWorld) throws { try world.validate() }

    func read() throws -> SceneWorld {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 32_768 else { throw StateStoreError.invalidSnapshot("背景设置文件过大") }
        let data = try Data(contentsOf: url)
        guard data.count <= 32_768 else { throw StateStoreError.invalidSnapshot("背景设置文件过大") }
        let world = try JSONDecoder().decode(SceneWorld.self, from: data)
        try Self.validate(world)
        return world
    }

    func write(_ world: SceneWorld) throws {
        try Self.validate(world)
        let data = try JSONEncoder().encode(world)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
