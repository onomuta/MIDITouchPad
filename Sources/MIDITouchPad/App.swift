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
                Button(engine.running ? LocalizedStringKey("Stop") : LocalizedStringKey("Start")) { engine.toggle() }
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
                    Text("Channel")
                    Stepper(value: $engine.channel, in: 1...16) {
                        Text("\(engine.channel)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("X CC")
                    Stepper(value: $engine.ccX, in: 0...127) {
                        Text("\(engine.ccX)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("Y CC")
                    Stepper(value: $engine.ccY, in: 0...127) {
                        Text("\(engine.ccY)").monospacedDigit()
                    }
                }
                GridRow {
                    Text("Touch base CC")
                    Stepper(value: $engine.ccTouch, in: 0...127) {
                        Text("\(engine.ccTouch)").monospacedDigit()
                    }
                }
            }
            .font(.caption)

            Divider()

            Toggle("Switch touch CC with number keys", isOn: Binding(
                get: { engine.keysEnabled },
                set: { engine.setKeysEnabled($0) }
            ))

            if engine.keysEnabled {
                if engine.keysGlobalActive {
                    Text("Active even when other apps are in front")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Currently active only while this panel is in front. To use it with other apps, allow MIDITouchPad in Input Monitoring (restart the app if it does not respond after allowing).")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Input Monitoring settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                        .font(.caption2)
                    }
                }
            }

            HStack {
                Text("Touch CC being sent")
                Spacer()
                Text("CC \(engine.activeTouchCC)")
                    .monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
            .font(.caption)

            Text("Keys 1–9 select base CC + 0–8; key 0 selects base CC + 9")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Invert Y", isOn: $engine.invertY)
            Toggle("14-bit resolution (LSB = CC+32)", isOn: $engine.highResolution)
            Toggle("Hold last value after release", isOn: $engine.holdLastValue)

            Divider()

            Text("Output: virtual port “\(engine.portName)”")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Quit") { NSApplication.shared.terminate(nil) }
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
