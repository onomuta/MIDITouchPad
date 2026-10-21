import AppKit

/// 数字キー 0〜9 を全域で監視する。
/// アクセシビリティ（入力監視）の許可が必要で、許可が無いとグローバル監視は無音で失敗する。
final class KeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onDigit: (Int) -> Void

    /// キーコード → 数字。テンキーも同じ数字として扱う。
    private static let digitKeyCodes: [UInt16: Int] = [
        29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]

    init(onDigit: @escaping (Int) -> Void) {
        self.onDigit = onDigit
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// 未許可なら「システム設定を開くか」の標準ダイアログを出す
    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        stop()
        // 他アプリ操作中に押されたキー
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // 自分のパネルが前面のときは global monitor に来ないので local でも拾う
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit { stop() }

    private func handle(_ event: NSEvent) {
        // ⌘ 併用はアプリ側のショートカットなので無視する
        guard !event.modifierFlags.contains(.command) else { return }
        guard let digit = Self.digitKeyCodes[event.keyCode] else { return }
        onDigit(digit)
    }
}
