// swift-tools-version: 5.9
import PackageDescription
import Foundation

let desktopEnabled: Bool = {
    #if os(Windows)
    return true
    #else
    return ProcessInfo.processInfo.environment["LOFTY_DESKTOP"] == "1"
    #endif
}()
var products: [Product] = [.executable(name: "TowerReplay", targets: ["TowerReplay"])]
var targets: [Target] = [
    .target(name: "TowerCore"),
    .target(name: "TowerSession", dependencies: ["TowerCore"]),
    .target(name: "TowerDesktopModel", dependencies: ["TowerCore", "TowerSession"]),
    .executableTarget(name: "TowerReplay", dependencies: ["TowerCore", "TowerSession"]),
    .target(name: "TowerArt", dependencies: ["TowerCore"], path: "Assets/Tokyo/Runtime", resources: [.copy("Sheets"), .copy("atlas.json"), .copy("TitleScreen.png")]),
    .target(name: "TowerPresentation", dependencies: ["TowerCore", "TowerArt"]),
    .testTarget(name: "TowerPresentationTests", dependencies: ["TowerCore", "TowerArt", "TowerPresentation"]),
    .testTarget(name: "TowerSessionTests", dependencies: ["TowerCore", "TowerSession"]),
    .testTarget(name: "TowerDesktopModelTests", dependencies: ["TowerCore", "TowerSession", "TowerDesktopModel"])
]
#if os(macOS)
products.append(.executable(name: "LoftyAmbitions", targets: ["TowerApp"]))
targets.append(.executableTarget(name: "TowerApp", dependencies: ["TowerCore", "TowerArt", "TowerSession", "TowerPresentation"]))
targets.append(.testTarget(name: "TowerCoreTests", dependencies: ["TowerCore", "TowerArt"]))
#else
targets.append(.testTarget(name: "TowerCoreTests", dependencies: ["TowerCore", "TowerArt"], exclude: ["ArtworkAssetsTests.swift", "ActorRegistrationTests.swift", "CloudTextureTests.swift"]))
#endif
if desktopEnabled {
    let sdlRoot = ProcessInfo.processInfo.environment["LOFTY_SDL_ROOT"] ?? ProcessInfo.processInfo.environment["SDL3_ROOT"] ?? "/opt/homebrew"
    #if os(Windows)
    let sdlLib = "\(sdlRoot)/lib/x64"
    #else
    let sdlLib = "\(sdlRoot)/lib"
    #endif
    targets.append(.target(name: "CDesktop", path: "Sources/CDesktop", exclude: ["README.md", "SDL-LICENSE.txt"], cSettings: [.unsafeFlags(["-I\(sdlRoot)/include"])], linkerSettings: [.unsafeFlags(["-L\(sdlLib)"]), .linkedLibrary("SDL3")]))
    targets.append(.executableTarget(name: "TowerDesktop", dependencies: ["TowerCore", "TowerSession", "TowerArt", "TowerPresentation", "TowerDesktopModel", "CDesktop"]))
    products.append(.executable(name: "LoftyDesktop", targets: ["TowerDesktop"]))
}
let package = Package(
    name: "LoftyAmbitions",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
