import CoreMIDI
import Foundation

/// "MIDITouchPad" という仮想 MIDI ソースを公開する。
/// DAW 側では MIDI 入力デバイスとして選択できる。
final class MIDIOutput {
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private(set) var isOpen = false

    let portName = "MIDITouchPad"

    func open() {
        guard !isOpen else { return }
        var status = MIDIClientCreate("MIDITouchPad Client" as CFString, nil, nil, &client)
        guard status == noErr else {
            NSLog("MIDIClientCreate failed: \(status)")
            return
        }
        status = MIDISourceCreate(client, portName as CFString, &source)
        guard status == noErr else {
            NSLog("MIDISourceCreate failed: \(status)")
            MIDIClientDispose(client)
            return
        }
        // 再起動しても DAW 側の割り当てが維持されるよう UID を固定する
        MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, 0x4D54_5041)
        isOpen = true
    }

    func close() {
        guard isOpen else { return }
        MIDIEndpointDispose(source)
        MIDIClientDispose(client)
        isOpen = false
    }

    deinit { close() }

    /// チャンネルは 1〜16 で指定
    func sendControlChange(channel: Int, cc: Int, value: Int) {
        let status = UInt8(0xB0 | ((channel - 1) & 0x0F))
        send([status, UInt8(cc & 0x7F), UInt8(value & 0x7F)])
    }

    func sendNoteOn(channel: Int, note: Int, velocity: Int) {
        let status = UInt8(0x90 | ((channel - 1) & 0x0F))
        send([status, UInt8(note & 0x7F), UInt8(velocity & 0x7F)])
    }

    func sendNoteOff(channel: Int, note: Int) {
        let status = UInt8(0x80 | ((channel - 1) & 0x0F))
        send([status, UInt8(note & 0x7F), 0])
    }

    private func send(_ bytes: [UInt8]) {
        guard isOpen else { return }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0,
                              bytes.count, bytes)
        MIDIReceived(source, &packetList)
    }
}
