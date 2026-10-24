import Foundation
import TowerCore
import TowerSession
#if os(Windows)
import ucrt
#elseif canImport(Glibc)
import Glibc
#else
import Darwin
#endif

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") || arguments.contains("-h") {
        print("Usage: TowerReplay --self-check [--output PATH] [--fixture PATH]")
        print("Replays a versioned command timeline, validates a save round-trip, and prints canonical JSON.")
        return
    }
    var output: URL?
    var fixture: URL?
    var index = 0
    while index < arguments.count {
        switch arguments[index] {
        case "--self-check": break
        case "--output", "--fixture":
            let flag = arguments[index]
            index += 1
            guard index < arguments.count else { throw TowerError("\(flag) requires a path.") }
            let url = URL(fileURLWithPath: arguments[index])
            if flag == "--output" { output = url } else { fixture = url }
        default: throw TowerError("Unknown argument: \(arguments[index])")
        }
        index += 1
    }
    let timeline: TowerReplayTimeline
    if let fixture { timeline = try JSONDecoder().decode(TowerReplayTimeline.self, from: Data(contentsOf: fixture)) }
    else { timeline = .selfCheck }
    let state = try timeline.run()
    let snapshot = try TowerSnapshot.canonicalData(state)
    let restored = try JSONDecoder().decode(TowerState.self, from: snapshot).validated()
    guard try TowerSnapshot.canonicalData(restored) == snapshot else {
        throw TowerError("Replay save round-trip changed the tower.")
    }
    if let output { try snapshot.write(to: output, options: .atomic) }
    FileHandle.standardOutput.write(snapshot)
    FileHandle.standardOutput.write(Data([10]))
}

do { try run() }
catch {
    FileHandle.standardError.write(Data("TowerReplay: \(error.localizedDescription)\n".utf8))
    exit(1)
}
