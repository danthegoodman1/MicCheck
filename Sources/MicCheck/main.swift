import Darwin
import Foundation

enum OutputMode {
    case short
    case detailed
}

struct CLIOptions: Equatable {
    let outputMode: OutputMode
    let debug: Bool

    static let usage = """
    Usage: MicCheck [--detailed] [--debug] [--help]

      MicCheck            Print 1 if any microphone input is active, otherwise 0
      MicCheck --detailed Print a JSON snapshot of microphone activity
      MicCheck --debug    Write debug logs to stderr
      MicCheck --help     Show this help text
    """

    init(arguments: [String]) throws {
        var outputMode: OutputMode = .short
        var debug = false

        for argument in arguments {
            switch argument {
            case "--detailed":
                outputMode = .detailed
            case "--debug":
                debug = true
            case "--help", "-h":
                throw CLIError.helpRequested
            default:
                throw CLIError.usage("Unknown argument: \(argument)")
            }
        }

        self.outputMode = outputMode
        self.debug = debug
    }
}

struct DeviceInfo: Equatable {
    let id: UInt32
    let name: String
    let uid: String?
    let manufacturer: String?
    let sampleRate: Double?
    let inputChannelCount: Int
    let transportType: String?
    let isAlive: Bool?
    let isRunningSomewhere: Bool?
    let isDefaultInput: Bool
}

extension DeviceInfo: Encodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case inputChannelCount
        case isAlive
        case isDefaultInput
        case isRunningSomewhere
        case manufacturer
        case name
        case sampleRate
        case transportType
        case uid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(inputChannelCount, forKey: .inputChannelCount)
        try container.encode(isDefaultInput, forKey: .isDefaultInput)
        try container.encode(name, forKey: .name)

        if let isAlive {
            try container.encode(isAlive, forKey: .isAlive)
        } else {
            try container.encodeNil(forKey: .isAlive)
        }

        if let isRunningSomewhere {
            try container.encode(isRunningSomewhere, forKey: .isRunningSomewhere)
        } else {
            try container.encodeNil(forKey: .isRunningSomewhere)
        }

        if let manufacturer {
            try container.encode(manufacturer, forKey: .manufacturer)
        } else {
            try container.encodeNil(forKey: .manufacturer)
        }

        if let sampleRate {
            try container.encode(sampleRate, forKey: .sampleRate)
        } else {
            try container.encodeNil(forKey: .sampleRate)
        }

        if let transportType {
            try container.encode(transportType, forKey: .transportType)
        } else {
            try container.encodeNil(forKey: .transportType)
        }

        if let uid {
            try container.encode(uid, forKey: .uid)
        } else {
            try container.encodeNil(forKey: .uid)
        }
    }
}

struct ProbeSnapshot: Equatable {
    let active: Bool
    let activeProcessCount: Int
    let activeDeviceCount: Int
    let device: DeviceInfo?
}

extension ProbeSnapshot: Encodable {
    private enum CodingKeys: String, CodingKey {
        case active
        case activeDeviceCount
        case activeProcessCount
        case device
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(active, forKey: .active)
        try container.encode(activeDeviceCount, forKey: .activeDeviceCount)
        try container.encode(activeProcessCount, forKey: .activeProcessCount)

        if let device {
            try container.encode(device, forKey: .device)
        } else {
            try container.encodeNil(forKey: .device)
        }
    }
}

protocol ProbeProviding {
    func snapshot(debugLog: (String) -> Void) throws -> ProbeSnapshot
}

enum CLIError: Error, Equatable {
    case helpRequested
    case usage(String)
    case runtime(String)
}

extension CLIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .helpRequested:
            return nil
        case let .usage(message):
            return message
        case let .runtime(message):
            return message
        }
    }
}

enum CLI {
    static func run(
        arguments: [String],
        probe: ProbeProviding,
        stdout: (String) -> Void,
        stderr: (String) -> Void
    ) -> Int32 {
        let options: CLIOptions
        do {
            options = try CLIOptions(arguments: arguments)
        } catch CLIError.helpRequested {
            stdout(CLIOptions.usage + "\n")
            return EXIT_SUCCESS
        } catch let CLIError.usage(message) {
            stderr(message + "\n\n" + CLIOptions.usage + "\n")
            return EX_USAGE
        } catch {
            stderr("Unexpected argument parsing error: \(error.localizedDescription)\n")
            return EXIT_FAILURE
        }

        let debugLog: (String) -> Void = { message in
            guard options.debug else { return }
            stderr("[debug] \(message)\n")
        }

        do {
            let snapshot = try probe.snapshot(debugLog: debugLog)
            let rendered = try render(snapshot: snapshot, mode: options.outputMode)
            stdout(rendered)
            return EXIT_SUCCESS
        } catch let cliError as CLIError {
            stderr((cliError.errorDescription ?? "MicCheck failed") + "\n")
            return EXIT_FAILURE
        } catch {
            stderr("MicCheck failed: \(error.localizedDescription)\n")
            return EXIT_FAILURE
        }
    }

    static func render(snapshot: ProbeSnapshot, mode: OutputMode) throws -> String {
        switch mode {
        case .short:
            return snapshot.active ? "1\n" : "0\n"
        case .detailed:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            guard let json = String(data: data, encoding: .utf8) else {
                throw CLIError.runtime("Failed to encode JSON output")
            }
            return json + "\n"
        }
    }
}

@main
struct MicCheckMain {
    static func main() {
        let exitCode = CLI.run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            probe: CoreAudioProbe(),
            stdout: { FileHandle.standardOutput.write(Data($0.utf8)) },
            stderr: { FileHandle.standardError.write(Data($0.utf8)) }
        )
        Darwin.exit(exitCode)
    }
}
