import Foundation

/// Installs only our own screen saver in the current user's Library. It never
/// changes the selected screen saver or the Mac's lock/sleep preferences.
struct ScreenSaverInstaller {
    static let bundleIdentifier = "com.virtualworkplace.screensaver"
    let applicationURL: URL
    let userLibraryURL: URL
    let fileManager: FileManager
    let verifySignature: (URL) throws -> Void

    struct Result {
        let destination: URL
        let version: String
        let replacedExisting: Bool
    }

    enum InstallationError: LocalizedError {
        case missingPayload
        case invalidBundle(String)
        case differentBundle
        case signature(String)
        var errorDescription: String? {
            switch self {
            case .missingPayload: return "应用内没有找到屏保安装文件，请重新下载完整的虚拟工位应用。"
            case .invalidBundle(let reason): return "屏保文件不完整：\(reason)"
            case .differentBundle: return "安装位置已有其他程序的同名屏保，已保留原文件。请先在 Finder 中检查。"
            case .signature(let reason): return "屏保校验未通过：\(reason)"
            }
        }
    }

    init(applicationURL: URL = Bundle.main.bundleURL,
         userLibraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"),
         fileManager: FileManager = .default,
         verifySignature: @escaping (URL) throws -> Void = ScreenSaverInstaller.verifyCodeSignature) {
        self.applicationURL = applicationURL
        self.userLibraryURL = userLibraryURL
        self.fileManager = fileManager
        self.verifySignature = verifySignature
    }

    var destination: URL { userLibraryURL.appendingPathComponent("Screen Savers/VirtualWorkplace.saver") }

    func install() throws -> Result {
        // Prefer the payload shipped with this application, rather than an old
        // sibling left next to a newer app. Siblings support local build output.
        let sibling = applicationURL.deletingLastPathComponent()
        let candidates = [applicationURL.appendingPathComponent("Contents/Resources/VirtualWorkplace.saver"),
                          sibling.appendingPathComponent("VirtualWorkplace.saver"),
                          sibling.appendingPathComponent("虚拟工位.saver")]
        guard let source = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw InstallationError.missingPayload
        }
        let metadata = try validateBundle(at: source)
        try verifySignature(source)
        let target = destination
        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let exists = fileManager.fileExists(atPath: target.path)
        if exists {
            // Refuse symlinks and differently owned bundles before moving any
            // existing item. The user may have another saver with this name.
            let attributes = try fileManager.attributesOfItem(atPath: target.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (try? bundleMetadata(at: target)["CFBundleIdentifier"] as? String) == Self.bundleIdentifier else {
                throw InstallationError.differentBundle
            }
        }
        let stage = parent.appendingPathComponent(".VirtualWorkplace-\(UUID().uuidString).saver")
        defer { try? fileManager.removeItem(at: stage) }
        try fileManager.copyItem(at: source, to: stage)
        _ = try validateBundle(at: stage)
        try verifySignature(stage)
        var backup: URL?
        if exists {
            let backupDirectory = userLibraryURL.appendingPathComponent("Application Support/VirtualWorkplace/Backups/ScreenSaver-\(UUID().uuidString)")
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let saved = backupDirectory.appendingPathComponent(target.lastPathComponent)
            try fileManager.moveItem(at: target, to: saved)
            backup = saved
        }
        do {
            try fileManager.moveItem(at: stage, to: target)
            _ = try validateBundle(at: target)
            try verifySignature(target)
        } catch {
            // A failed update restores the previous plugin, including if final
            // signature verification catches a damaged copy.
            try? fileManager.removeItem(at: target)
            if let backup { try? fileManager.moveItem(at: backup, to: target) }
            throw error
        }
        return Result(destination: target, version: metadata["CFBundleShortVersionString"] as? String ?? "", replacedExisting: exists)
    }

    private func bundleMetadata(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw InstallationError.invalidBundle("无法读取屏保信息")
        }
        return result
    }

    private func validateBundle(at url: URL) throws -> [String: Any] {
        let metadata = try bundleMetadata(at: url)
        guard metadata["CFBundleIdentifier"] as? String == Self.bundleIdentifier,
              metadata["CFBundlePackageType"] as? String == "BNDL",
              metadata["NSPrincipalClass"] as? String == "VirtualWorkplaceSaverView",
              let executable = metadata["CFBundleExecutable"] as? String,
              executable == "VirtualWorkplace" else {
            throw InstallationError.invalidBundle("不是虚拟工位屏保")
        }
        for path in ["Contents/MacOS/\(executable)", "Contents/Resources/Room/cabin-background.png", "Contents/Resources/Room/employee-kit.png"] {
            guard fileManager.fileExists(atPath: url.appendingPathComponent(path).path) else {
                throw InstallationError.invalidBundle("缺少 \(URL(fileURLWithPath: path).lastPathComponent)")
            }
        }
        return metadata
    }

    private static func verifyCodeSignature(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--strict", url.path]
        let output = Pipe()
        process.standardError = output
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data.prefix(2048), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "签名无效"
            throw InstallationError.signature(detail)
        }
    }
}
