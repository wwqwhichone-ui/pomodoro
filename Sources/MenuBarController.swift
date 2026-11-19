// macOS 顶部菜单栏控制器：实时显示倒计时与阶段，点击提供快捷控制与窗口切换
import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private weak var model: TimerModel?
    private weak var wm: WindowManager?
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var lastRendered: (symbol: String, text: String)?

    func start(model: TimerModel, wm: WindowManager) {
        self.model = model
        self.wm = wm
        cancellable = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
        setEnabled(UserDefaults.standard.bool(forKey: Key.menuBar))
    }

    func setEnabled(_ on: Bool) {
        if on {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                statusItem = item
            }
            lastRendered = nil
            refresh()
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            lastRendered = nil
        }
    }

    private func refresh() {
        guard let item = statusItem, let button = item.button, let model else { return }
        let symbol = (!model.isRunning && model.hasStarted) ? "pause.circle" : model.phase.symbol
        let text = (model.isRunning || model.hasStarted) ? " \(model.timeText)" : ""

        if lastRendered?.symbol == symbol && lastRendered?.text == text { return }
        lastRendered = (symbol, text)

        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "番茄钟")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)]
        )
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }

        let summary = NSMenuItem(title: "\(model.phase.title) · \(model.timeText)", action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)

        if model.phase == .focus, let task = model.currentTask {
            let taskItem = NSMenuItem(title: "当前：\(task.title)", action: nil, keyEquivalent: "")
            taskItem.isEnabled = false
            menu.addItem(taskItem)
        }

        menu.addItem(.separator())

        let toggleTitle = model.isRunning ? "暂停" : (model.hasStarted ? "继续" : (model.phase == .focus ? "开始专注" : "开始休息"))
        menu.addItem(makeItem(toggleTitle, action: #selector(toggleTimer)))
        menu.addItem(makeItem("重置", action: #selector(resetTimer)))
        menu.addItem(makeItem(model.phase == .focus ? "放弃本番茄" : "结束休息", action: #selector(skipTimer)))

        if model.phase == .focus {
            menu.addItem(makeItem("记录内部打断（-）", action: #selector(logInternal)))
            menu.addItem(makeItem("记录外部打断（=）", action: #selector(logExternal)))
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("显示主窗口", action: #selector(showMainWindow)))

        let miniItem = makeItem("迷你悬浮窗", action: #selector(toggleMini))
        miniItem.state = (wm?.isMini == true) ? .on : .off
        menu.addItem(miniItem)

        if wm?.sidecarAvailable == true {
            if wm?.isOnIPad == true {
                menu.addItem(makeItem("移回 Mac", action: #selector(sendToMac)))
            } else {
                menu.addItem(makeItem("发送到 iPad 并全屏", action: #selector(sendToIPad)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("退出番茄钟", action: #selector(quitApp), key: "q"))
    }

    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleTimer() { model?.toggle() }
    @objc private func resetTimer() { model?.reset() }
    @objc private func skipTimer() { model?.skip() }
    @objc private func logInternal() { model?.logInterruption(internal: true) }
    @objc private func logExternal() { model?.logInterruption(internal: false) }

    @objc private func showMainWindow() {
        NSApp.activate()
        if wm?.window?.isMiniaturized == true {
            wm?.window?.deminiaturize(nil)
        }
        wm?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleMini() {
        guard let wm else { return }
        showMainWindow()
        wm.setMini(!wm.isMini)
    }

    @objc private func sendToIPad() { wm?.sendToIPad() }
    @objc private func sendToMac() { wm?.sendToMac() }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
