import SwiftUI

/// 起動と同時に送信を開始する（メニューを開かなくても使えるように）
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        TouchEngine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchEngine.shared.stop()
    }
}

@main
struct MIDITouchPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = TouchEngine.shared

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(engine: engine)
        } label: {
            Image(systemName: engine.running ? "hand.point.up.left.fill" : "hand.point.up.left")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ControlPanel: View {
    @ObservedObject var engine: TouchEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MIDITouchPad").font(.headline)
                Spacer()
                Button(engine.running ? "停止" : "開始") { engine.toggle() }
                    .keyboardShortcut(.defaultAction)
            }

            Text(engine.statusMessage)
                .font(.caption)
                .foregroundStyle(engine.running ? .green : .secondary)

            TouchPadView(engine: engine)
                .frame(height: 140)

            HStack {
                readout("X", engine.x)
                readout("Y", engine.y)
                readout("Touch", engine.touching ? 1 : 0)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("チャンネル")
                    Stepper(value: $engine.channel, in: 1...16) {
                        Text("\(engine.channel)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("X の CC")
                    Stepper(value: $engine.ccX, in: 0...127) {
                        Text("\(engine.ccX)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("Y の CC")
                    Stepper(value: $engine.ccY, in: 0...127) {
                        Text("\(engine.ccY)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("タッチの基準 CC")
                    Stepper(value: $engine.ccTouch, in: 0...127) {
                        Text("\(engine.ccTouch)").monospacedDigit()
                    }
                }
            }
            .font(.caption)

            Divider()

            Toggle("数字キーでタッチ CC を切り替え", isOn: Binding(
                get: { engine.keysEnabled },
                set: { engine.setKeysEnabled($0) }
            ))

            if engine.keysEnabled {
                if engine.keysGlobalActive {
                    Text("他のアプリが前面でも有効です")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("現在はこのパネルが前面のときだけ有効です。他のアプリでも使うには「入力監視」で MIDITouchPad を許可してください（許可後に反応しなければ、アプリを再起動）。")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Button("入力監視の設定を開く") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                        .font(.caption2)
                    }
                }
            }

            HStack {
                Text("送信中のタッチ CC")
                Spacer()
                Text("CC \(engine.activeTouchCC)")
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
            .font(.caption)

            Text("1〜9 で 基準 CC + 0〜8、0 で 基準 CC + 9 を選択")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Y を上下反転", isOn: $engine.invertY)
            Toggle("14bit 解像度 (LSB = CC+32)", isOn: $engine.highResolution)
            Toggle("離しても最後の値を保持", isOn: $engine.holdLastValue)

            Divider()

            Text("出力先: 仮想ポート「\(engine.portName)」")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("終了") { NSApplication.shared.terminate(nil) }
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .padding(14)
        .frame(width: 300)
    }

    private func readout(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.3f", value)).monospacedDigit().font(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 現在のタッチ位置を表示するだけのビュー（操作はしない）
struct TouchPadView: View {
    @ObservedObject var engine: TouchEngine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.3))

                Circle()
                    .fill(engine.touching ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .position(
                        x: engine.x * geo.size.width,
                        y: (1 - engine.y) * geo.size.height
                    )
                    .animation(.linear(duration: 0.03), value: engine.x)
                    .animation(.linear(duration: 0.03), value: engine.y)
            }
        }
    }
}
