import AppKit
import ScreenSaver
import os

/// A read-only host. Simulation and state persistence belong to the companion app.
@objc(VirtualWorkplaceSaverView)
final class VirtualWorkplaceSaverView: ScreenSaverView {
    private let logger = Logger(subsystem: "com.virtualworkplace.screensaver", category: "lifecycle")
    private let store = StateStore()
    private let sceneAnimation = SceneAnimation()
    private var lastValidSnapshot = SceneSnapshot.empty()
    private var startRequested = false
    private var screenSleeping = false
    private var lastPollTime: TimeInterval = -.infinity
    private var observerTokens: [(NotificationCenter, NSObjectProtocol)] = []
    private weak var observedWindow: NSWindow?
    private var hasLoggedReadError = false
    private var lastFreshness: Bool?
    private var lastTaskCount: Int?
    private let diagnosticInstance = String(UUID().uuidString.prefix(8))
    private var lifecycleStates: [String: String] = [:]
    private var loggedInitialDraw = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        observerTokens.forEach { $0.0.removeObserver($0.1) }
    }

    private func configure() {
        animationTimeInterval = 1.0 / 30.0
        lastValidSnapshot.isOnline = false
        logger.info("Created screen saver; read-only state path: \(StateStore.defaultURL.path, privacy: .public)")
        logLifecycle("configure")
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.screenSleeping = true
            self?.reconcileAnimation()
        }
        observe(workspaceCenter, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.screenSleeping = false
            self?.lastPollTime = -.infinity
            self?.reconcileAnimation()
        }
        observe(NotificationCenter.default, NSWindow.didChangeOcclusionStateNotification) { [weak self] in
            self?.reconcileAnimation()
        }
        let closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let closingWindow = notification.object as? NSWindow,
                  closingWindow === self.observedWindow else { return }
            self.startRequested = false
            self.reconcileAnimation()
        }
        observerTokens.append((NotificationCenter.default, closeToken))
        pollState(at: ProcessInfo.processInfo.systemUptime)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observerTokens.append((center, token))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observedWindow = window
        logLifecycle("viewDidMoveToWindow")
        reconcileAnimation()
    }

    override func viewDidHide() {
        super.viewDidHide()
        reconcileAnimation()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        reconcileAnimation()
    }

    override func startAnimation() {
        startRequested = true
        lastPollTime = -.infinity
        logLifecycle("startAnimation entry")
        reconcileAnimation()
    }

    override func stopAnimation() {
        startRequested = false
        logLifecycle("stopAnimation entry")
        reconcileAnimation()
    }

    private var canRender: Bool {
        guard startRequested, !screenSleeping, !isHiddenOrHasHiddenAncestor,
              let attached = observedWindow, attached === window, attached.isVisible else { return false }
        if attached.occlusionState.contains(.visible) { return true }

        // The system's remote screen saver window can be visible on the active
        // Space without the AppKit .visible occlusion bit set. Keep the normal
        // occlusion requirement for all other windows.
        guard attached.isOnActiveSpace,
              let remoteWindowClass = NSClassFromString("NSServiceViewControllerWindow") else { return false }
        return attached.isKind(of: remoteWindowClass)
    }

    private func reconcileAnimation() {
        if canRender {
            guard !isAnimating else { return }
            let remoteFallback = observedWindow?.occlusionState.contains(.visible) == false
            logLifecycle("reconcile allowed", extra: "remoteOcclusionFallback=\(remoteFallback)")
            sceneAnimation.reset()
            pollState(at: ProcessInfo.processInfo.systemUptime)
            animationTimeInterval = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 1.0 / 30.0
            super.startAnimation()
            logger.info("Animation started; bounds \(self.bounds.width)x\(self.bounds.height)")
            needsDisplay = true
        } else {
            logLifecycle("reconcile rejected")
            if isAnimating {
                super.stopAnimation()
                sceneAnimation.reset()
                logger.info("Animation stopped; no active visible screen saver")
            }
        }
    }

    /// Report the host's visibility signals once per stable event, including
    /// when frames are rejected or the remote window fallback is used.
    private func logLifecycle(_ event: String, extra: String = "") {
        let attached = observedWindow
        let windowClass = attached.map { String(describing: type(of: $0)) } ?? "nil"
        let frame = attached.map { String(describing: $0.frame) } ?? "nil"
        let occlusion = attached.map { String(format: "0x%llx", UInt64($0.occlusionState.rawValue)) } ?? "nil"
        let state = "instance=\(diagnosticInstance) windowClass=\(windowClass) frame=\(frame) bounds=\(bounds) viewHasWindow=\(window != nil) windowMatches=\(attached === window) visible=\(attached?.isVisible ?? false) occlusion=\(occlusion) activeSpace=\(attached?.isOnActiveSpace ?? false) isPreview=\(isPreview) startRequested=\(startRequested) sleeping=\(screenSleeping) hidden=\(isHiddenOrHasHiddenAncestor) animating=\(isAnimating) \(extra)"
        guard lifecycleStates[event] != state else { return }
        lifecycleStates[event] = state
        logger.info("Lifecycle \(event, privacy: .public): \(state, privacy: .public)")
    }

    override func animateOneFrame() {
        guard canRender else {
            reconcileAnimation()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPollTime >= 1.0 { pollState(at: now) }
        needsDisplay = true
    }

    private func pollState(at time: TimeInterval) {
        lastPollTime = time
        do {
            lastValidSnapshot = try store.read()
            if hasLoggedReadError {
                logger.info("State file is readable again")
                hasLoggedReadError = false
            }
        } catch {
            if !hasLoggedReadError {
                logger.notice("State read failed; preserving last valid scene: \(String(describing: error), privacy: .public)")
                hasLoggedReadError = true
            }
        }
        let fresh = lastValidSnapshot.isFresh()
        if lastFreshness != fresh {
            logger.info("State freshness changed; online=\(fresh)")
            lastFreshness = fresh
        }
        if lastTaskCount != lastValidSnapshot.tasks.count {
            logger.info("Scene task count changed; tasks=\(self.lastValidSnapshot.tasks.count)")
            lastTaskCount = lastValidSnapshot.tasks.count
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPollTime >= 1 { pollState(at: now) }
        if !isAnimating { sceneAnimation.reset() }
        let background = renderedBackground
        let viewport = renderedViewport
        if !loggedInitialDraw {
            loggedInitialDraw = true
            logLifecycle("first draw", extra: "background=\(background.rawValue) display=\(viewport.display) roomAssets=\(SceneRenderer.hasRoomAssets)")
        }
        SceneRenderer.draw(
            in: context,
            bounds: bounds,
            snapshot: lastValidSnapshot,
            time: ProcessInfo.processInfo.systemUptime,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            animation: sceneAnimation,
            background: background,
            viewport: viewport
        )
    }

    override var isOpaque: Bool { true }
    override var hasConfigureSheet: Bool { false }

    private var usesRoomPreview: Bool {
        // Some legacy hosts mark a full-screen instance as a preview. Only a
        // small settings thumbnail uses the fixed room camera on this target.
        isPreview && bounds.width > 0 && bounds.height > 0
            && bounds.width <= 640 && bounds.height <= 480
    }

    private var renderedBackground: WorkplaceBackground {
        // The small settings preview represents the room. It does not write or
        // infer a monitor assignment from the settings window's current screen.
        guard !usesRoomPreview else { return .room }
        return DisplaySceneRouting.background(for: DisplaySceneRouting.screen(for: window ?? observedWindow),
            world: lastValidSnapshot.world ?? SceneWorld(), context: .screenSaver)
    }

    private var renderedViewport: WorldViewport {
        if usesRoomPreview { return .companion(for: .room) }
        let screen = DisplaySceneRouting.screen(for: window ?? observedWindow)
        return DisplaySceneRouting.viewport(for: screen, world: lastValidSnapshot.world ?? SceneWorld(),
                                           context: .screenSaver) ?? .companion(for: renderedBackground)
    }

    /// Read-only probes used by the separate diagnostic host, never by the system UI.
    @objc var diagnosticTaskCount: Int { lastValidSnapshot.tasks.count }
    @objc var diagnosticPendingNoteCount: Int { lastValidSnapshot.pendingNotes?.count ?? 0 }
    @objc var diagnosticEffectiveWeather: String { lastValidSnapshot.effectiveWorld(at: Date()).weather.rawValue }
    @objc var diagnosticStatePath: String { store.url.path }
    @objc var diagnosticIsOnline: Bool { lastValidSnapshot.isFresh() }
    @objc var diagnosticUsesCartoonCharacter: Bool { SceneRenderer.hasRoomAssets }
    @objc var diagnosticBackground: String { renderedBackground.rawValue }
    @objc func diagnosticPollState() {
        pollState(at: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }
}
