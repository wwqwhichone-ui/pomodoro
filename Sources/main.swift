// 番茄钟 —— SwiftUI 应用入口，用 swiftc 直接编译（见 build.sh）
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = TimerModel()
    @StateObject private var wm = WindowManager.shared

    var body: some Scene {
        Window("番茄钟", id: "main") {
            ContentView(model: model, wm: wm)
                .frame(minWidth: 260, minHeight: 84)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: WindowManager.normalSize.width, height: WindowManager.normalSize.height)
        .commands {
            CommandMenu("计时") {
                Button("开始 / 暂停") { model.toggle() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("重置") { model.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("跳过本段") { model.skip() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("记录内部打断（-）") { model.logInterruption(internal: true) }
                Button("记录外部打断（=）") { model.logInterruption(internal: false) }
            }
            CommandGroup(after: .windowArrangement) {
                Divider()
                Button("发送到 iPad 并全屏") { wm.sendToIPad() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("移回 Mac") { wm.sendToMac() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button("迷你悬浮窗") { wm.setMini(!wm.isMini) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}

PomodoroApp.main()
