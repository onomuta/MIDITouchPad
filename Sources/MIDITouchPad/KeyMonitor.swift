import AppKit

/// 数字キー 0〜9 を全域で監視する。
///
/// 他アプリが前面のときにキーを拾うには「入力監視」の許可が必要。許可が無いと
/// CGEventTap の作成が失敗するので、その間は自分のパネルが前面のときだけ
/// 反応する local monitor にフォールバックする。
final class KeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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

    /// 入力監視の許可が下りているか
    var hasListenAccess: Bool { CGPreflightListenEventAccess() }

    /// 他アプリ前面時にもキーを拾えている（イベントタップが動いている）か
    var isGlobalActive: Bool { tap != nil }

    /// 未許可なら許可ダイアログを出し、システム設定の「入力監視」一覧にアプリを登録する
    @discardableResult
    func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    /// 監視を開始する。全域のタップを作れたら true、フォールバックだけなら false。
    @discardableResult
    func start() -> Bool {
        stop()
        if installTap() { return true }
        // 許可が無い間は、自分のパネルが前面のときだけでも拾えるようにしておく
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(keyCode: event.keyCode, command: event.modifierFlags.contains(.command))
            return event
        }
        return false
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        tap = nil
        runLoopSource = nil
        localMonitor = nil
    }

    deinit { stop() }

    // MARK: - イベントタップ

    private func installTap() -> Bool {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        // listenOnly: キーを横取りも改変もしない。見るだけ。
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    fileprivate func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(keyCode: UInt16, command: Bool) {
        // ⌘ 併用はアプリ側のショートカットなので無視する
        guard !command else { return }
        guard let digit = Self.digitKeyCodes[keyCode] else { return }
        onDigit(digit)
    }
}

/// CGEventTap は C 関数ポインタしか受け付けないので、userInfo 経由で KeyMonitor に戻る。
private let keyTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // システムが遅延などでタップを止めたら、すぐに有効へ戻す
        monitor.reenableTap()
    case .keyDown:
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat {
            monitor.handle(
                keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                command: event.flags.contains(.maskCommand)
            )
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
