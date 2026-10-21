// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MIDITouchPad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MIDITouchPad",
            path: "Sources/MIDITouchPad"
        )
    ]
)
