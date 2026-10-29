// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LewtechRecord",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "LewtechRecord", targets: ["LewtechRecord"])],
    targets: [
        .executableTarget(name: "LewtechRecord", resources: [.process("Resources")], linkerSettings: [.linkedFramework("AVKit")])
    ]
)
