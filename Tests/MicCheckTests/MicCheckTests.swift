import CoreAudio
import XCTest
@testable import MicCheck

final class MicCheckTests: XCTestCase {
    func testDefaultModePrintsActiveFlag() {
        let snapshot = ProbeSnapshot(
            active: true,
            activeProcessCount: 2,
            activeDeviceCount: 1,
            device: nil
        )

        let output = try? CLI.render(snapshot: snapshot, mode: .short)
        XCTAssertEqual(output, "1\n")
    }

    func testDetailedModePrintsStableJSON() throws {
        let snapshot = ProbeSnapshot(
            active: true,
            activeProcessCount: 1,
            activeDeviceCount: 1,
            device: DeviceInfo(
                id: 7,
                name: "Built-in Microphone",
                uid: "BuiltInMic",
                manufacturer: "Apple",
                sampleRate: 48_000,
                inputChannelCount: 2,
                transportType: "builtIn",
                isAlive: true,
                isRunningSomewhere: true,
                isDefaultInput: true
            )
        )

        let output = try CLI.render(snapshot: snapshot, mode: .detailed)
        XCTAssertEqual(
            output,
            #"{"active":true,"activeDeviceCount":1,"activeProcessCount":1,"device":{"id":7,"inputChannelCount":2,"isAlive":true,"isDefaultInput":true,"isRunningSomewhere":true,"manufacturer":"Apple","name":"Built-in Microphone","sampleRate":48000,"transportType":"builtIn","uid":"BuiltInMic"}}"# + "\n"
        )
    }

    func testUnknownFlagReturnsUsageError() {
        let probe = StubProbe(snapshot: .success(.inactiveSnapshot))
        var stdout = ""
        var stderr = ""

        let exitCode = CLI.run(
            arguments: ["--wat"],
            probe: probe,
            stdout: { stdout += $0 },
            stderr: { stderr += $0 }
        )

        XCTAssertEqual(exitCode, EX_USAGE)
        XCTAssertTrue(stdout.isEmpty)
        XCTAssertTrue(stderr.contains("Unknown argument: --wat"))
        XCTAssertTrue(stderr.contains("Usage: MicCheck"))
    }

    func testDebugLogsGoToStderrOnly() {
        let probe = StubProbe(snapshot: .success(.activeSnapshot))
        var stdout = ""
        var stderr = ""

        let exitCode = CLI.run(
            arguments: ["--debug"],
            probe: probe,
            stdout: { stdout += $0 },
            stderr: { stderr += $0 }
        )

        XCTAssertEqual(exitCode, EXIT_SUCCESS)
        XCTAssertEqual(stdout, "1\n")
        XCTAssertTrue(stderr.contains("[debug] stub probe invoked"))
    }

    func testSnapshotBuilderPrefersActiveDefaultInput() {
        let defaultDeviceID: AudioObjectID = 2
        let deviceInfos: [AudioObjectID: DeviceInfo] = [
            2: DeviceInfo(
                id: 2,
                name: "Default Mic",
                uid: "default",
                manufacturer: "Apple",
                sampleRate: 48_000,
                inputChannelCount: 1,
                transportType: "builtIn",
                isAlive: true,
                isRunningSomewhere: true,
                isDefaultInput: true
            ),
            9: DeviceInfo(
                id: 9,
                name: "USB Mic",
                uid: "usb",
                manufacturer: "Shure",
                sampleRate: 44_100,
                inputChannelCount: 1,
                transportType: "usb",
                isAlive: true,
                isRunningSomewhere: true,
                isDefaultInput: false
            ),
        ]

        let snapshot = SnapshotBuilder.makeSnapshot(
            activeProcessCount: 1,
            activeDeviceIDs: [9, 2],
            deviceInfos: deviceInfos,
            defaultInputDeviceID: defaultDeviceID
        )

        XCTAssertEqual(snapshot.device?.id, 2)
    }

    func testSnapshotBuilderUsesFallbackActiveDevicesWhenProcessCountIsZero() {
        let deviceInfos: [AudioObjectID: DeviceInfo] = [
            4: DeviceInfo(
                id: 4,
                name: "Fallback Mic",
                uid: "fallback",
                manufacturer: nil,
                sampleRate: nil,
                inputChannelCount: 1,
                transportType: nil,
                isAlive: true,
                isRunningSomewhere: true,
                isDefaultInput: false
            )
        ]

        let snapshot = SnapshotBuilder.makeSnapshot(
            activeProcessCount: 0,
            activeDeviceIDs: [4],
            deviceInfos: deviceInfos,
            defaultInputDeviceID: nil
        )

        XCTAssertTrue(snapshot.active)
        XCTAssertEqual(snapshot.activeProcessCount, 0)
        XCTAssertEqual(snapshot.activeDeviceCount, 1)
        XCTAssertEqual(snapshot.device?.id, 4)
    }
}

private struct StubProbe: ProbeProviding {
    let snapshot: Result<ProbeSnapshot, Error>

    func snapshot(debugLog: (String) -> Void) throws -> ProbeSnapshot {
        debugLog("stub probe invoked")
        return try snapshot.get()
    }
}

private extension ProbeSnapshot {
    static let activeSnapshot = ProbeSnapshot(
        active: true,
        activeProcessCount: 1,
        activeDeviceCount: 1,
        device: nil
    )

    static let inactiveSnapshot = ProbeSnapshot(
        active: false,
        activeProcessCount: 0,
        activeDeviceCount: 0,
        device: nil
    )
}
