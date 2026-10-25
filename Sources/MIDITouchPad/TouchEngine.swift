import Foundation
import SwiftUI

/// トラックパッドのタッチを読んで MIDI に変換する本体。
/// MTRegisterContactFrameCallback は C 関数ポインタしか受け付けず context を渡せないので、
/// shared 経由でコールバックから実体に戻る。
final class TouchEngine: ObservableObject {
    static let shared = TouchEngine()

    // 表示用（UI スレッドで更新）
    @Published private(set) var x: Double = 0.5
    @Published private(set) var y: Double = 0.5
    @Published private(set) var touching = false
    @Published private(set) var running = false
    @Published private(set) var statusMessage = String(localized: "Stopped")

    // 設定（UserDefaults に永続化）
    @Published var channel: Int { didSet { save(channel, "channel") } }
    @Published var ccX: Int { didSet { save(ccX, "ccX") } }
    @Published var ccY: Int { didSet { save(ccY, "ccY") } }
    /// タッチ CC の基準値。実際に使う CC は基準 + 選択中スロット。
    @Published var ccTouch: Int { didSet { save(ccTouch, "ccTouch") } }
    /// 最後に押された数字キーで決まるスロット（1〜9 → 0〜8、0 → 9）
    @Published private(set) var touchSlot: Int = 0
    @Published private(set) var keysEnabled = false
    /// 他アプリが前面でもキーを拾えている（入力監視が許可され、タップが動いている）か
    @Published private(set) var keysGlobalActive = false
    var hasListenAccess: Bool { keyMonitor?.hasListenAccess ?? CGPreflightListenEventAccess() }
    @Published var invertY: Bool { didSet { save(invertY, "invertY") } }
    @Published var highResolution: Bool { didSet { save(highResolution, "highResolution") } }
    @Published var holdLastValue: Bool { didSet { save(holdLastValue, "holdLastValue") } }

    private let midi = MIDIOutput()
    private var devices: [MTDeviceRef] = []
    private var keyMonitor: KeyMonitor?
    private var keyRetryTimer: Timer?

    /// いま実際に送信しているタッチ CC
    var activeTouchCC: Int { min(ccTouch + touchSlot, 127) }

    // コールバックスレッドから触る状態
    private var activeTouchID: Int32?
    private var lastSentX = -1
    private var lastSentY = -1
    private var lastSentTouch = -1
    private let touchLock = NSLock()

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "channel": 1, "ccX": 1, "ccY": 2, "ccTouch": 64,
            "invertY": false, "highResolution": false, "holdLastValue": true,
        ])
        channel = d.integer(forKey: "channel")
        ccX = d.integer(forKey: "ccX")
        ccY = d.integer(forKey: "ccY")
        ccTouch = d.integer(forKey: "ccTouch")
        invertY = d.bool(forKey: "invertY")
        highResolution = d.bool(forKey: "highResolution")
        holdLastValue = d.bool(forKey: "holdLastValue")
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    var portName: String { midi.portName }

    // MARK: - 開始 / 停止

    func start() {
        guard !running else { return }
        guard MultitouchSupport.isAvailable else {
            statusMessage = String(localized: "Could not load MultitouchSupport")
            return
        }
        midi.open()
        guard midi.isOpen else {
            statusMessage = String(localized: "Could not create the MIDI port")
            return
        }
        devices = MultitouchSupport.deviceList()
        guard !devices.isEmpty else {
            statusMessage = String(localized: "No trackpad found")
            return
        }
        for device in devices {
            MultitouchSupport.register(device, touchCallback)
            MultitouchSupport.start(device)
        }
        running = true
        statusMessage = devices.count == 1
            ? String(localized: "Sending (1 device)")
            : String(localized: "Sending (\(devices.count) devices)")
    }

    func stop() {
        guard running else { return }
        for device in devices {
            MultitouchSupport.stop(device)
            MultitouchSupport.unregister(device, touchCallback)
        }
        devices = []
        setKeysEnabled(false)
        releaseActiveTouch()
        midi.close()
        running = false
        touching = false
        statusMessage = String(localized: "Stopped")
    }

    func toggle() { running ? stop() : start() }

    // MARK: - タッチ処理（コールバックスレッド）

    fileprivate func handle(touches: UnsafeMutablePointer<MTTouch>?, count: Int32) {
        var current: MTTouch?

        if let touches {
            let buffer = UnsafeBufferPointer(start: touches, count: Int(count))
            // 追跡中の指を最優先。いなければ接触中で最も若い identifier を採用する。
            if let id = activeTouchID,
               let t = buffer.first(where: { $0.identifier == id && mtIsTouching($0.state) }) {
                current = t
            } else {
                current = buffer.filter { mtIsTouching($0.state) }
                    .min(by: { $0.identifier < $1.identifier })
            }
        }

        guard let touch = current else {
            releaseActiveTouch()
            return
        }

        activeTouchID = touch.identifier
        let nx = Double(min(max(touch.normalized.position.x, 0), 1))
        let rawY = Double(min(max(touch.normalized.position.y, 0), 1))
        // MultitouchSupport の y は手前が 0。画面と同じ「上が大きい」向きに揃える。
        let ny = invertY ? 1 - rawY : rawY

        sendPosition(nx, ny)
        sendTouch(true)

        DispatchQueue.main.async {
            self.x = nx
            self.y = ny
            self.touching = true
        }
    }

    private func releaseActiveTouch() {
        guard activeTouchID != nil else { return }
        activeTouchID = nil
        sendTouch(false)
        if !holdLastValue {
            sendPosition(0, 0)
        }
        DispatchQueue.main.async { self.touching = false }
    }

    private func sendPosition(_ nx: Double, _ ny: Double) {
        if highResolution {
            send14bit(cc: ccX, value: nx, last: &lastSentX)
            send14bit(cc: ccY, value: ny, last: &lastSentY)
        } else {
            send7bit(cc: ccX, value: nx, last: &lastSentX)
            send7bit(cc: ccY, value: ny, last: &lastSentY)
        }
    }

    private func send7bit(cc: Int, value: Double, last: inout Int) {
        let v = Int((value * 127).rounded())
        guard v != last else { return }
        last = v
        midi.sendControlChange(channel: channel, cc: cc, value: v)
    }

    /// MSB を cc、LSB を cc+32 に載せる標準的な 14bit CC。
    private func send14bit(cc: Int, value: Double, last: inout Int) {
        let v = Int((value * 16383).rounded())
        guard v != last else { return }
        last = v
        midi.sendControlChange(channel: channel, cc: cc, value: v >> 7)
        midi.sendControlChange(channel: channel, cc: cc + 32, value: v & 0x7F)
    }

    /// タッチ送信はコールバックスレッドとキー監視（メインスレッド）の両方から呼ばれるので、
    /// lastSentTouch の読み書きは必ずロックの内側で行う。
    private func sendTouch(_ on: Bool) {
        touchLock.lock()
        defer { touchLock.unlock() }
        sendTouchLocked(on)
    }

    private func sendTouchLocked(_ on: Bool) {
        let v = on ? 127 : 0
        guard v != lastSentTouch else { return }
        lastSentTouch = v
        midi.sendControlChange(channel: channel, cc: activeTouchCC, value: v)
    }

    // MARK: - 数字キーによるタッチ CC の切り替え

    /// 数字キー押下。1〜9 はスロット 0〜8、0 はスロット 9。
    func selectSlot(fromDigit digit: Int) {
        let slot = digit == 0 ? 9 : digit - 1
        guard slot != touchSlot else {
            return
        }

        touchLock.lock()
        // 切り替え前の CC を必ず 0 に戻す。押しっぱなしのまま置き去りにしない。
        let wasHeld = lastSentTouch == 127
        if wasHeld {
            midi.sendControlChange(channel: channel, cc: activeTouchCC, value: 0)
        }
        touchSlot = slot
        lastSentTouch = 0
        // 指が触れたままの切り替えなら、新しい CC で押し直す
        if wasHeld {
            sendTouchLocked(true)
        }
        touchLock.unlock()
    }

    /// 数字キー監視の有効・無効。
    /// 入力監視が未許可でも start() は自分のパネル前面時のみ動くフォールバックで続行する。
    func setKeysEnabled(_ enabled: Bool) {
        keyRetryTimer?.invalidate()
        keyRetryTimer = nil
        if enabled {
            let monitor = keyMonitor ?? KeyMonitor { [weak self] digit in
                self?.selectSlot(fromDigit: digit)
            }
            keyMonitor = monitor
            monitor.requestPermission()
            keysGlobalActive = monitor.start()
            keysEnabled = true
            if !keysGlobalActive { scheduleKeyRetry() }
        } else {
            keyMonitor?.stop()
            keysEnabled = false
            keysGlobalActive = false
        }
    }

    /// 許可を後から与えたときに、トグルを入れ直さなくても全域監視へ切り替わるようにする。
    private func scheduleKeyRetry() {
        keyRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, let monitor = self.keyMonitor, self.keysEnabled else {
                timer.invalidate()
                return
            }
            if monitor.hasListenAccess, monitor.start() {
                self.keysGlobalActive = true
                timer.invalidate()
                self.keyRetryTimer = nil
            }
        }
    }
}

private let touchCallback: MTContactCallback = { _, touches, count, _, _ in
    let typed = touches?.bindMemory(to: MTTouch.self, capacity: Int(max(count, 0)))
    TouchEngine.shared.handle(touches: typed, count: count)
    return 0
}
