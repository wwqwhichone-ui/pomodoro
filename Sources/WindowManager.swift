// 窗口管理：识别所在屏幕（Mac / iPad 随航）、自动全屏、一键发送到 iPad / 移回 Mac、迷你悬浮窗
import AppKit
import SwiftUI

final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published private(set) var isOnIPad = false
    @Published private(set) var isFullScreen = false
    @Published private(set) var sidecarAvailable = false
    @Published private(set) var isMini = false

    private(set) weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var autoFullScreened = false
    private var fullScreenPending = false
    private var afterExitFullScreen: (() -> Void)?
    private var savedFrame: NSRect?
    private var lastMacFrame: NSRect?
    private var compactChrome = false
    private let d = UserDefaults.standard

    static let normalSize = NSSize(width: 440, height: 640)
    static let miniSize = NSSize(width: 320, height: 104)

    // MARK: 屏幕识别

    /// 随航屏幕的名字形如「Sidecar Display (AirPlay)」
    static func isSidecar(_ screen: NSScreen?) -> Bool {
        guard let n = screen?.localizedName.lowercased() else { return false }
        return n.contains("sidecar") || n.contains("ipad") || n.contains("随航")
    }
    var sidecarScreen: NSScreen? { NSScreen.screens.first { Self.isSidecar($0) } }
    var macScreen: NSScreen? { NSScreen.screens.first { !Self.isSidecar($0) } }

    // MARK: 绑定窗口

    func attach(_ w: NSWindow) {
        guard window !== w else { return }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        window = w
        w.isMovableByWindowBackground = true
        w.collectionBehavior.insert(.fullScreenPrimary)
        isFullScreen = w.styleMask.contains(.fullScreen)

        observe(NSWindow.didChangeScreenNotification, w) { [weak self] in self?.screenChanged() }
        observe(NSApplication.didChangeScreenParametersNotification, nil) { [weak self] in self?.screenChanged() }
        observe(NSWindow.didEnterFullScreenNotification, w) { [weak self] in
            self?.isFullScreen = true
            self?.fullScreenPending = false
        }
        observe(NSWindow.didExitFullScreenNotification, w) { [weak self] in
            guard let self else { return }
            self.isFullScreen = false
            self.autoFullScreened = false
            if let next = self.afterExitFullScreen {
                self.afterExitFullScreen = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: next)
            }
        }
        observe(NSWindow.didMoveNotification, w) { [weak self] in self?.rememberMacFrame() }
        observe(NSWindow.didEndLiveResizeNotification, w) { [weak self] in self?.rememberMacFrame() }

        // 上次退出时是迷你窗：恢复迷你状态（置顶）
        isMini = Self.isCompact(w.frame.size)
        applyOnTop()
        applyChrome()
        DispatchQueue.main.async { w.makeFirstResponder(nil) }
        screenChanged(force: true)
    }

    private func observe(_ name: Notification.Name, _ object: Any?, _ handler: @escaping () -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name, object: object, queue: .main) { _ in handler() })
    }

    private func screenChanged(force: Bool = false) {
        sidecarAvailable = sidecarScreen != nil
        guard let w = window else { return }
        let onPad = Self.isSidecar(w.screen)
        guard onPad != isOnIPad || force else { return }
        isOnIPad = onPad
        if onPad {
            if isMini {
                isMini = false
                applyOnTop()
            }
            if d.bool(forKey: Key.autoFullScreen) { requestFullScreen() }
        } else if isFullScreen && autoFullScreened {
            // 随航断开、窗口被系统挪回 Mac：退出我们自动进入的全屏
            w.toggleFullScreen(nil)
        }
    }

    /// 等拖动松手后再全屏（拖动途中切全屏会很突兀）
    private func requestFullScreen(attempt: Int = 0) {
        if attempt == 0 {
            guard !fullScreenPending else { return }
            fullScreenPending = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, let w = self.window else { return }
            guard Self.isSidecar(w.screen), !self.isFullScreen else {
                self.fullScreenPending = false
                return
            }
            if NSEvent.pressedMouseButtons != 0 && attempt < 120 {
                self.requestFullScreen(attempt: attempt + 1)
                return
            }
            self.autoFullScreened = true
            w.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.fullScreenPending = false }
        }
    }

    private func rememberMacFrame() {
        guard let w = window, !isFullScreen, !isMini, !compactChrome, !Self.isSidecar(w.screen) else { return }
        lastMacFrame = w.frame
    }

    // MARK: 用户操作

    func toggleFullScreen() { window?.toggleFullScreen(nil) }

    func sendToIPad() {
        guard let w = window, let s = sidecarScreen else { return }
        if isFullScreen {
            afterExitFullScreen = { [weak self] in self?.sendToIPad() }
            w.toggleFullScreen(nil)
            return
        }
        if isMini { setMini(false) }
        rememberMacFrame()
        let vf = s.visibleFrame
        let size = NSSize(width: min(Self.normalSize.width, vf.width), height: min(Self.normalSize.height, vf.height))
        w.setFrame(Self.centered(size, in: vf), display: true)
        requestFullScreen()
    }

    func sendToMac() {
        guard let w = window, let s = macScreen else { return }
        if isFullScreen {
            afterExitFullScreen = { [weak self] in self?.sendToMac() }
            autoFullScreened = false
            w.toggleFullScreen(nil)
            return
        }
        let vf = s.visibleFrame
        let target = lastMacFrame.flatMap { vf.intersects($0) ? $0 : nil }
            ?? Self.centered(Self.normalSize, in: vf)
        w.setFrame(target, display: true)
    }

    func setMini(_ on: Bool) {
        guard let w = window else { return }
        if on {
            guard !isMini, !isFullScreen else { return }
            // 已经是迷你尺寸（比如上次退出时就是迷你窗）就不记，展开时回到标准尺寸
            savedFrame = Self.isCompact(w.frame.size) ? nil : w.frame
            isMini = true
            applyOnTop()
            let vf = (w.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let s = Self.miniSize
            w.setFrame(NSRect(x: vf.maxX - s.width - 16, y: vf.maxY - s.height - 16,
                              width: s.width, height: s.height), display: true, animate: true)
        } else {
            let target = (isMini ? savedFrame : nil).flatMap { Self.isCompact($0.size) ? nil : $0 }
                ?? lastMacFrame.flatMap { Self.isCompact($0.size) ? nil : $0 }
                ?? NSRect(x: w.frame.maxX - Self.normalSize.width, y: w.frame.maxY - Self.normalSize.height,
                          width: Self.normalSize.width, height: Self.normalSize.height)
            isMini = false
            savedFrame = nil
            applyOnTop()
            w.setFrame(w.constrainFrameRect(target, to: w.screen), display: true, animate: true)
        }
    }

    func applyOnTop() {
        window?.level = (isMini || d.bool(forKey: Key.onTop)) ? .floating : .normal
    }

    /// 迷你布局时隐藏红绿灯按钮
    func setCompactChrome(_ compact: Bool) {
        compactChrome = compact
        applyChrome()
    }

    private func applyChrome() {
        guard let w = window else { return }
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            w.standardWindowButton(b)?.isHidden = compactChrome
        }
    }

    /// 与 LayoutKind.mini 的判定保持一致
    static func isCompact(_ size: NSSize) -> Bool { size.height < 190 || size.width < 240 }

    private static func centered(_ size: NSSize, in vf: NSRect) -> NSRect {
        NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// 拿到 SwiftUI 窗口对应的 NSWindow
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
    }
}

/// 全局快捷键：空格 开始/暂停，- 内部打断，= 外部打断（正在输入文字时不拦截）。
/// 按物理键位识别（Delete 左边相邻的两个键），切到中文输入法也能用。
enum KeyMonitor {
    /// Carbon 虚拟键码：kVK_Space / kVK_ANSI_Minus / kVK_ANSI_Equal
    private enum Code {
        static let space: UInt16 = 49
        static let minus: UInt16 = 27
        static let equal: UInt16 = 24
    }

    private static var installed = false
    static func install(_ model: TimerModel) {
        guard !installed else { return }
        installed = true
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard mods.isEmpty, !e.isARepeat, !(NSApp.keyWindow?.firstResponder is NSText) else { return e }
            switch e.keyCode {
            case Code.space: model.toggle(); return nil
            case Code.minus: model.logInterruption(internal: true); return nil
            case Code.equal: model.logInterruption(internal: false); return nil
            default: return e
            }
        }
    }
}
