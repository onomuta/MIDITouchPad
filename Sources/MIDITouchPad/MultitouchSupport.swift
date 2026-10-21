import Foundation

// MultitouchSupport は非公開フレームワークなのでヘッダが無い。
// dlopen/dlsym で必要な 4 関数だけを取り出して使う。

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// MultitouchSupport が callback に渡す 1 タッチ分の構造体。
/// C 側の定義とフィールド順・型を厳密に合わせること（レイアウト互換に依存している）。
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var zero2: Int32
    var zero3: Int32
    var zDensity: Float
}

/// state == 3 (make touch) / 4 (touching) を「接触中」とみなす。
/// 1,2 は接近・ホバー、5〜7 は離脱途中。
func mtIsTouching(_ state: Int32) -> Bool {
    state == 3 || state == 4
}

typealias MTDeviceRef = UnsafeMutableRawPointer
/// 実際の C 側シグネチャは
/// `int (*)(MTDeviceRef, MTTouch*, int numTouches, double timestamp, int frame)`。
/// Swift 構造体は @convention(c) の引数に使えないので raw pointer で受け、
/// 呼び出し側で MTTouch に bind し直す。
typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

enum MultitouchSupport {
    private typealias CreateListFn = @convention(c) () -> UnsafeMutableRawPointer?
    // callback は関数ポインタのまま渡す。Swift のジェネリクス推論が
    // 「引数が関数型の @convention(c) 型」を扱えないので raw pointer で受ける。
    private typealias RegisterFn = @convention(c) (MTDeviceRef, UnsafeRawPointer) -> Void
    private typealias UnregisterFn = @convention(c) (MTDeviceRef, UnsafeRawPointer) -> Void
    private typealias StartFn = @convention(c) (MTDeviceRef, Int32) -> Int32
    private typealias StopFn = @convention(c) (MTDeviceRef) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_LAZY
    )

    private static func sym<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static var isAvailable: Bool { handle != nil }

    /// MTDeviceCreateList が返す配列を解放するとデバイス参照ごと無効になるので、
    /// プロセスが生きている間はここで保持し続ける。
    private static var retainedDeviceList: CFArray?

    /// 接続されている全マルチタッチデバイス（内蔵トラックパッド / Magic Trackpad）
    static func deviceList() -> [MTDeviceRef] {
        guard let fn = sym("MTDeviceCreateList", as: CreateListFn.self),
              let raw = fn() else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        retainedDeviceList = array
        let count = CFArrayGetCount(array)
        return (0..<count).compactMap { i in
            CFArrayGetValueAtIndex(array, i).map { UnsafeMutableRawPointer(mutating: $0) }
        }
    }

    static func register(_ device: MTDeviceRef, _ callback: MTContactCallback) {
        guard let handle, let p = dlsym(handle, "MTRegisterContactFrameCallback") else { return }
        let fn = unsafeBitCast(p, to: RegisterFn.self)
        fn(device, unsafeBitCast(callback, to: UnsafeRawPointer.self))
    }

    static func unregister(_ device: MTDeviceRef, _ callback: MTContactCallback) {
        guard let handle, let p = dlsym(handle, "MTUnregisterContactFrameCallback") else { return }
        let fn = unsafeBitCast(p, to: UnregisterFn.self)
        fn(device, unsafeBitCast(callback, to: UnsafeRawPointer.self))
    }

    /// 戻り値は 0 が成功。失敗理由の切り分けに使う。
    @discardableResult
    static func start(_ device: MTDeviceRef) -> Int32 {
        guard let fn = sym("MTDeviceStart", as: StartFn.self) else { return -1 }
        return fn(device, 0)
    }

    static func stop(_ device: MTDeviceRef) {
        sym("MTDeviceStop", as: StopFn.self)?(device)
    }
}
