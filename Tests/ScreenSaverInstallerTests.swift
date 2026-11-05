import Foundation

@main
struct ScreenSaverInstallerTests {
    static var checks = 0
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        guard value else { fatalError("FAIL: \(message)") }
    }
    static func main() throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent("WorkplaceInstallerTests-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let app = temporary.appendingPathComponent("虚拟工位.app")
        let library = temporary.appendingPathComponent("Library")
        let embedded = app.appendingPathComponent("Contents/Resources/VirtualWorkplace.saver")
        func makeBundle(_ url: URL, version: String, identifier: String = ScreenSaverInstaller.bundleIdentifier) throws {
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            try fm.createDirectory(at: url.appendingPathComponent("Contents/Resources/Room"), withIntermediateDirectories: true)
            let metadata = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "BNDL",
                            "NSPrincipalClass": "VirtualWorkplaceSaverView", "CFBundleExecutable": "VirtualWorkplace",
                            "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            for path in ["Contents/MacOS/VirtualWorkplace", "Contents/Resources/Room/cabin-background.png", "Contents/Resources/Room/employee-kit.png"] {
                try Data(version.utf8).write(to: url.appendingPathComponent(path))
            }
        }
        func versionAt(_ url: URL) throws -> String {
            let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
            return (try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any])["CFBundleShortVersionString"] as! String
        }
        let installer = ScreenSaverInstaller(applicationURL: app, userLibraryURL: library, verifySignature: { _ in })
        do { _ = try installer.install(); fatalError("missing payload accepted") }
        catch { check(error is ScreenSaverInstaller.InstallationError, "missing payload is actionable") }
        try makeBundle(embedded, version: "new")
        try makeBundle(temporary.appendingPathComponent("VirtualWorkplace.saver"), version: "old")
        let installed = try installer.install()
        check(!installed.replacedExisting, "fresh install reported")
        check(installed.version == "new", "embedded payload preferred to stale sibling")
        check(try versionAt(installed.destination) == "new", "correct installed version")
        check(installed.destination.path == library.appendingPathComponent("Screen Savers/VirtualWorkplace.saver").path, "only user library target")
        try fm.removeItem(at: embedded)
        try makeBundle(embedded, version: "newer")
        let updated = try installer.install()
        check(updated.replacedExisting, "existing install updates")
        check(try versionAt(updated.destination) == "newer", "updated version installed")
        let backups = try fm.contentsOfDirectory(at: library.appendingPathComponent("Application Support/VirtualWorkplace/Backups"), includingPropertiesForKeys: nil)
        check(backups.count == 1, "one previous bundle retained")
        check(try versionAt(backups[0].appendingPathComponent("VirtualWorkplace.saver")) == "new", "backup preserves previous version")
        let rejected = ScreenSaverInstaller(applicationURL: app, userLibraryURL: library, verifySignature: { _ in
            throw ScreenSaverInstaller.InstallationError.signature("fixture")
        })
        do { _ = try rejected.install(); fatalError("invalid signature accepted") } catch { }
        check(try versionAt(updated.destination) == "newer", "signature rejection preserves installation")
        var verifications = 0
        let rollback = ScreenSaverInstaller(applicationURL: app, userLibraryURL: library, verifySignature: { _ in
            verifications += 1
            if verifications == 3 { throw ScreenSaverInstaller.InstallationError.signature("final copy") }
        })
        do { _ = try rollback.install(); fatalError("invalid final copy accepted") } catch { }
        check(verifications == 3, "source, stage and installed signature checked")
        check(try versionAt(updated.destination) == "newer", "final validation failure restores old installation")
        let files = try fm.contentsOfDirectory(atPath: updated.destination.deletingLastPathComponent().path)
        check(!files.contains(where: { $0.hasPrefix(".VirtualWorkplace-") }), "staging bundle cleaned")
        try fm.removeItem(at: updated.destination)
        try makeBundle(updated.destination, version: "other", identifier: "example.other")
        do { _ = try installer.install(); fatalError("other bundle replaced") } catch { }
        check(try versionAt(updated.destination) == "other", "different bundle retained")
        try fm.removeItem(at: updated.destination)
        try fm.createSymbolicLink(at: updated.destination, withDestinationURL: embedded)
        do { _ = try installer.install(); fatalError("symlink destination replaced") } catch { }
        check(try fm.destinationOfSymbolicLink(atPath: updated.destination.path) == embedded.path, "symlink destination retained")
        try fm.removeItem(at: updated.destination)
        try fm.removeItem(at: embedded.appendingPathComponent("Contents/Resources/Room/employee-kit.png"))
        do { _ = try installer.install(); fatalError("incomplete payload accepted") } catch { }
        check(!fm.fileExists(atPath: updated.destination.path), "incomplete payload never installed")
        print("PASS: \(checks) screen saver installation checks")
    }
}
