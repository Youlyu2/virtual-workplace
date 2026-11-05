import AppKit
import CoreGraphics

private final class ImmersiveWindow: NSWindow {
    var onExit: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?() }
        else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onExit?() }
}

/// Owns only this app's presentation windows. Desktop pictures and system settings
/// remain untouched, so disabling the mode immediately reveals the user's wallpaper.
final class ScenePresentationController {
    private var immersiveWindow: ImmersiveWindow?
    private var immersiveScene: WorkplaceSceneView?
    private var desktopWindows: [NSWindow] = []
    private var desktopScenes: [WorkplaceSceneView] = []
    private var desktopDisplayIDs: [String] = []
    private var snapshot: SceneSnapshot = .empty()
    private var displayObserver: NSObjectProtocol?
    var onExitImmersive: (() -> Void)?
    var onWallpaperChanged: ((Bool) -> Void)?
    private(set) var wallpaperEnabled = false
    var immersiveEnabled: Bool { immersiveWindow != nil }

    init() {
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
    }

    deinit {
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        closeAll()
    }

    func update(_ snapshot: SceneSnapshot) {
        self.snapshot = snapshot
        immersiveScene?.snapshot = snapshot
        let world = snapshot.world ?? SceneWorld()
        if let scene = immersiveScene {
            let screen = DisplaySceneRouting.screen(for: immersiveWindow)
            scene.background = DisplaySceneRouting.background(for: screen, world: world)
            scene.viewport = DisplaySceneRouting.viewport(for: screen, world: snapshot.world ?? SceneWorld())
        }
        for (index, pair) in zip(desktopWindows, desktopScenes).enumerated() {
            let (window, scene) = pair
            let screen = desktopScreen(at: index, window: window)
            scene.snapshot = snapshot
            scene.background = DisplaySceneRouting.background(for: screen, world: world)
            scene.viewport = DisplaySceneRouting.viewport(for: screen, world: snapshot.world ?? SceneWorld())
        }
    }

    func showImmersive(on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        if let window = immersiveWindow { window.makeKeyAndOrderFront(nil); return }
        let window = ImmersiveWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "虚拟工位 · 沉浸全屏（Esc 返回）"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .normal
        window.backgroundColor = .black
        let scene = WorkplaceSceneView(frame: CGRect(origin: .zero, size: screen.frame.size))
        scene.snapshot = snapshot
        scene.background = DisplaySceneRouting.background(for: screen, world: snapshot.world ?? SceneWorld())
        scene.viewport = DisplaySceneRouting.viewport(for: screen, world: snapshot.world ?? SceneWorld())
        scene.autoresizingMask = [.width, .height]
        scene.maximumFramesPerSecond = 30
        window.contentView = scene
        window.onExit = { [weak self] in self?.hideImmersive(returnToControls: true) }
        immersiveWindow = window
        immersiveScene = scene
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scene.startAnimating()
    }

    func hideImmersive(returnToControls: Bool) {
        immersiveScene?.stopAnimating()
        immersiveWindow?.onExit = nil
        immersiveWindow?.orderOut(nil)
        immersiveWindow?.close()
        immersiveScene = nil
        immersiveWindow = nil
        if returnToControls { onExitImmersive?() }
    }

    func setWallpaperEnabled(_ enabled: Bool) {
        guard enabled != wallpaperEnabled else { return }
        wallpaperEnabled = enabled
        if enabled { rebuildDesktopWindows() }
        else { removeDesktopWindows() }
        onWallpaperChanged?(enabled)
    }

    func stopAnimations() {
        immersiveScene?.stopAnimating()
        desktopScenes.forEach { $0.stopAnimating() }
    }

    func resumeAnimations() {
        immersiveScene?.startAnimating()
        desktopScenes.forEach { $0.startAnimating() }
    }

    func closeAll() {
        hideImmersive(returnToControls: false)
        removeDesktopWindows()
        wallpaperEnabled = false
    }

    private func screensChanged() {
        if wallpaperEnabled { rebuildDesktopWindows() }
        if let window = immersiveWindow {
            let screen = window.screen ?? NSScreen.main
            if let screen {
                window.setFrame(screen.frame, display: true)
                immersiveScene?.background = DisplaySceneRouting.background(for: screen, world: snapshot.world ?? SceneWorld())
                immersiveScene?.viewport = DisplaySceneRouting.viewport(for: screen, world: snapshot.world ?? SceneWorld())
            }
        }
    }

    private func removeDesktopWindows() {
        desktopScenes.forEach { $0.stopAnimating() }
        for window in desktopWindows { window.orderOut(nil); window.close() }
        desktopScenes.removeAll()
        desktopWindows.removeAll()
        desktopDisplayIDs.removeAll()
    }

    private func rebuildDesktopWindows() {
        removeDesktopWindows()
        for screen in NSScreen.screens {
            let window = Self.makeDesktopWindow(frame: screen.frame)
            let scene = WorkplaceSceneView(frame: CGRect(origin: .zero, size: screen.frame.size))
            scene.maximumFramesPerSecond = 15
            scene.autoresizingMask = [.width, .height]
            scene.snapshot = snapshot
            scene.background = DisplaySceneRouting.background(for: screen, world: snapshot.world ?? SceneWorld())
            scene.viewport = DisplaySceneRouting.viewport(for: screen, world: snapshot.world ?? SceneWorld())
            window.contentView = scene
            desktopWindows.append(window)
            desktopScenes.append(scene)
            desktopDisplayIDs.append(DisplaySceneRouting.identity(for: screen))
            window.orderFrontRegardless()
            scene.startAnimating()
        }
    }

    /// Read-only diagnostics of the scene actually assigned to each owned desktop
    /// window. Focus and window ordering never select another display's scene.
    func diagnosticDisplayScenes() -> [[String: Any]] {
        zip(desktopWindows, desktopScenes).enumerated().map { index, pair in
            let (window, scene) = pair
            let screen = desktopScreen(at: index, window: window)
            return ["id": screen.map { DisplaySceneRouting.identity(for: $0) } ?? "unavailable",
                    "name": screen?.localizedName ?? "未连接显示器",
                    "background": scene.background.rawValue,
                    "windowFrame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
                    "ignoresMouseEvents": window.ignoresMouseEvents,
                    "worldCanvas": scene.viewport.map { [$0.canvas.minX, $0.canvas.minY, $0.canvas.width, $0.canvas.height] } ?? [],
                    "worldDisplay": scene.viewport.map { [$0.display.minX, $0.display.minY, $0.display.width, $0.display.height] } ?? []]
        }
    }

    private func desktopScreen(at index: Int, window: NSWindow) -> NSScreen? {
        if desktopDisplayIDs.indices.contains(index),
           let target = NSScreen.screens.first(where: { DisplaySceneRouting.identity(for: $0) == desktopDisplayIDs[index] }) {
            return target
        }
        return DisplaySceneRouting.screen(for: window)
    }

    private static func makeDesktopWindow(frame: CGRect) -> NSWindow {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let ownLevel = NSWindow.Level(rawValue: min(desktopLevel + 1, iconLevel - 1))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "虚拟工位 · 桌面背景"
        window.isReleasedWhenClosed = false
        window.level = ownLevel
        window.ignoresMouseEvents = true
        window.canHide = false
        window.acceptsMouseMovedEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.animationBehavior = .none
        window.backgroundColor = .black
        return window
    }

    /// Runs without ordering any window, changing wallpaper, or taking input.
    static func checkConfiguration() throws -> String {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let desktop = makeDesktopWindow(frame: frame)
        defer { desktop.close() }
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        guard desktop.ignoresMouseEvents, !desktop.canHide, !desktop.acceptsMouseMovedEvents,
              !desktop.canBecomeKey, !desktop.canBecomeMain, !desktop.isVisible,
              desktop.level.rawValue < iconLevel,
              desktop.collectionBehavior.contains(.canJoinAllSpaces),
              desktop.collectionBehavior.contains(.stationary),
              desktop.collectionBehavior.contains(.ignoresCycle) else {
            throw NSError(domain: "VirtualWorkplace.Presentation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Desktop background would intercept input or overlap icons"])
        }
        let immersive = ImmersiveWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        immersive.isReleasedWhenClosed = false
        defer { immersive.close() }
        var escaped = false
        immersive.onExit = { escaped = true }
        immersive.cancelOperation(nil)
        guard escaped, immersive.canBecomeKey, !immersive.isVisible else {
            throw NSError(domain: "VirtualWorkplace.Presentation", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Immersive exit callback is unavailable"])
        }
        return "PASS: click-through desktop background below icons, all Spaces, invisible construction; immersive Escape exit callback"
    }
}
