import CoreAudio
import Foundation

struct CoreAudioProbe: ProbeProviding {
    func snapshot(debugLog: (String) -> Void) throws -> ProbeSnapshot {
        let defaultInputDeviceID = try? defaultInputDevice()
        var deviceInfos = try inputDeviceInfos(defaultInputDeviceID: defaultInputDeviceID)

        if let defaultInputDeviceID {
            debugLog("Default input device ID: \(defaultInputDeviceID)")
        } else {
            debugLog("No default input device is currently available")
        }

        if let defaultInputDeviceID, deviceInfos[defaultInputDeviceID] == nil, let defaultInfo = try? makeDeviceInfo(
            deviceID: defaultInputDeviceID,
            defaultInputDeviceID: defaultInputDeviceID
        ) {
            deviceInfos[defaultInputDeviceID] = defaultInfo
        }

        do {
            let processSnapshot = try activeInputFromProcesses(debugLog: debugLog)
            let snapshot = SnapshotBuilder.makeSnapshot(
                activeProcessCount: processSnapshot.activeProcessCount,
                activeDeviceIDs: processSnapshot.activeDeviceIDs,
                deviceInfos: deviceInfos,
                defaultInputDeviceID: defaultInputDeviceID
            )
            debugLog(snapshotDescription(snapshot, source: "process objects"))
            return snapshot
        } catch {
            debugLog("Process-based detection failed: \(error.localizedDescription)")
            let fallback = try activeInputFromDevices(deviceInfos: deviceInfos)
            let snapshot = SnapshotBuilder.makeSnapshot(
                activeProcessCount: 0,
                activeDeviceIDs: fallback.activeDeviceIDs,
                deviceInfos: deviceInfos,
                defaultInputDeviceID: defaultInputDeviceID
            )
            debugLog(snapshotDescription(snapshot, source: "device fallback"))
            return snapshot
        }
    }
}

struct ProcessActivitySnapshot {
    let activeProcessCount: Int
    let activeDeviceIDs: Set<AudioObjectID>
}

enum SnapshotBuilder {
    static func makeSnapshot(
        activeProcessCount: Int,
        activeDeviceIDs: Set<AudioObjectID>,
        deviceInfos: [AudioObjectID: DeviceInfo],
        defaultInputDeviceID: AudioObjectID?
    ) -> ProbeSnapshot {
        let primaryDeviceID = primaryDeviceID(
            activeDeviceIDs: activeDeviceIDs,
            deviceInfos: deviceInfos,
            defaultInputDeviceID: defaultInputDeviceID
        )

        return ProbeSnapshot(
            active: !activeDeviceIDs.isEmpty,
            activeProcessCount: activeProcessCount,
            activeDeviceCount: activeDeviceIDs.count,
            device: primaryDeviceID.flatMap { deviceInfos[$0] }
        )
    }

    static func primaryDeviceID(
        activeDeviceIDs: Set<AudioObjectID>,
        deviceInfos: [AudioObjectID: DeviceInfo],
        defaultInputDeviceID: AudioObjectID?
    ) -> AudioObjectID? {
        if !activeDeviceIDs.isEmpty {
            if let defaultInputDeviceID, activeDeviceIDs.contains(defaultInputDeviceID) {
                return defaultInputDeviceID
            }
            return activeDeviceIDs.sorted().first
        }

        if let defaultInputDeviceID, deviceInfos[defaultInputDeviceID] != nil {
            return defaultInputDeviceID
        }

        return nil
    }
}

private extension CoreAudioProbe {
    func activeInputFromProcesses(debugLog: (String) -> Void) throws -> ProcessActivitySnapshot {
        let processObjectIDs: [AudioObjectID] = try getArrayProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyProcessObjectList,
            scope: kAudioObjectPropertyScopeGlobal
        )

        debugLog("Found \(processObjectIDs.count) audio process objects")

        var activeProcessCount = 0
        var activeDeviceIDs = Set<AudioObjectID>()

        for processObjectID in processObjectIDs {
            let isRunningInput: UInt32 = try getScalarProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningInput,
                scope: kAudioObjectPropertyScopeGlobal
            )

            guard isRunningInput != 0 else { continue }

            activeProcessCount += 1

            let inputDevices: [AudioObjectID] = try getArrayProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyDevices,
                scope: kAudioObjectPropertyScopeInput
            )

            debugLog("Process \(processObjectID) reports input devices \(inputDevices)")
            inputDevices.forEach { activeDeviceIDs.insert($0) }
        }

        return ProcessActivitySnapshot(
            activeProcessCount: activeProcessCount,
            activeDeviceIDs: activeDeviceIDs
        )
    }

    func activeInputFromDevices(deviceInfos: [AudioObjectID: DeviceInfo]) throws -> ProcessActivitySnapshot {
        let activeDeviceIDs = Set(
            deviceInfos.values
                .filter { $0.isRunningSomewhere == true }
                .map { AudioObjectID($0.id) }
        )

        if activeDeviceIDs.isEmpty {
            return ProcessActivitySnapshot(
                activeProcessCount: 0,
                activeDeviceIDs: activeDeviceIDs
            )
        }

        let sortedDeviceIDs = activeDeviceIDs.sorted()
        return ProcessActivitySnapshot(
            activeProcessCount: 0,
            activeDeviceIDs: Set(sortedDeviceIDs)
        )
    }

    func inputDeviceInfos(defaultInputDeviceID: AudioObjectID?) throws -> [AudioObjectID: DeviceInfo] {
        let deviceIDs: [AudioObjectID] = try getArrayProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )

        var result: [AudioObjectID: DeviceInfo] = [:]
        for deviceID in deviceIDs {
            let inputChannelCount = try getInputChannelCount(deviceID: deviceID)
            guard inputChannelCount > 0 else { continue }

            let deviceInfo = try makeDeviceInfo(
                deviceID: deviceID,
                defaultInputDeviceID: defaultInputDeviceID,
                inputChannelCountOverride: inputChannelCount
            )
            result[deviceID] = deviceInfo
        }

        return result
    }

    func defaultInputDevice() throws -> AudioObjectID {
        try getScalarProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    func makeDeviceInfo(
        deviceID: AudioObjectID,
        defaultInputDeviceID: AudioObjectID?,
        inputChannelCountOverride: Int? = nil
    ) throws -> DeviceInfo {
        let inputChannelCount = try inputChannelCountOverride ?? getInputChannelCount(deviceID: deviceID)

        return DeviceInfo(
            id: UInt32(deviceID),
            name: (try? getStringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            )) ?? "Unknown",
            uid: try? getStringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            manufacturer: try? getStringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyManufacturer,
                scope: kAudioObjectPropertyScopeGlobal
            ),
            sampleRate: try? getScalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyNominalSampleRate,
                scope: kAudioObjectPropertyScopeGlobal
            ) as Double,
            inputChannelCount: inputChannelCount,
            transportType: (try? getScalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyTransportType,
                scope: kAudioObjectPropertyScopeGlobal
            ) as UInt32).flatMap(transportTypeName),
            isAlive: (try? getScalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceIsAlive,
                scope: kAudioObjectPropertyScopeGlobal
            ) as UInt32).map { $0 != 0 },
            isRunningSomewhere: (try? getScalarProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                scope: kAudioObjectPropertyScopeGlobal
            ) as UInt32).map { $0 != 0 },
            isDefaultInput: deviceID == defaultInputDeviceID
        )
    }

    func getInputChannelCount(deviceID: AudioObjectID) throws -> Int {
        var address = makeAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeInput
        )

        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw CoreAudioError.status(sizeStatus, selector: address.mSelector)
        }

        guard size > 0 else {
            return 0
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        var mutableSize = size
        let dataStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &mutableSize, rawBuffer)
        guard dataStatus == noErr else {
            throw CoreAudioError.status(dataStatus, selector: address.mSelector)
        }

        let audioBufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(audioBufferList).reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    func getScalarProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> T {
        var address = makeAddress(selector: selector, scope: scope)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }

        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, value)
        guard status == noErr else {
            throw CoreAudioError.status(status, selector: selector)
        }

        return value.move()
    }

    func getArrayProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> [T] {
        var address = makeAddress(selector: selector, scope: scope)
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw CoreAudioError.status(sizeStatus, selector: selector)
        }

        guard size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<T>.stride
        var values = Array<T>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            initializedCount = count
        }
        var mutableSize = size
        let dataStatus = values.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(objectID, &address, 0, nil, &mutableSize, baseAddress)
        }

        guard dataStatus == noErr else {
            throw CoreAudioError.status(dataStatus, selector: selector)
        }

        return values
    }

    func getStringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) throws -> String {
        var address = makeAddress(selector: selector, scope: scope)
        var stringValue: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &stringValue) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }

        guard status == noErr else {
            throw CoreAudioError.status(status, selector: selector)
        }

        guard let stringValue else {
            throw CoreAudioError.missingValue(selector: selector)
        }

        return stringValue as String
    }

    func makeAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func transportTypeName(_ rawValue: UInt32) -> String? {
        switch rawValue {
        case kAudioDeviceTransportTypeUnknown:
            return "unknown"
        case kAudioDeviceTransportTypeBuiltIn:
            return "builtIn"
        case kAudioDeviceTransportTypeAggregate:
            return "aggregate"
        case kAudioDeviceTransportTypeVirtual:
            return "virtual"
        case kAudioDeviceTransportTypePCI:
            return "pci"
        case kAudioDeviceTransportTypeUSB:
            return "usb"
        case kAudioDeviceTransportTypeFireWire:
            return "fireWire"
        case kAudioDeviceTransportTypeBluetooth:
            return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "bluetoothLE"
        case kAudioDeviceTransportTypeHDMI:
            return "hdmi"
        case kAudioDeviceTransportTypeDisplayPort:
            return "displayPort"
        case kAudioDeviceTransportTypeAirPlay:
            return "airPlay"
        case kAudioDeviceTransportTypeAVB:
            return "avb"
        case kAudioDeviceTransportTypeThunderbolt:
            return "thunderbolt"
        case kAudioDeviceTransportTypeContinuityCaptureWired:
            return "continuityCaptureWired"
        case kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "continuityCaptureWireless"
        default:
            return nil
        }
    }

    func snapshotDescription(_ snapshot: ProbeSnapshot, source: String) -> String {
        let deviceName = snapshot.device?.name ?? "none"
        return "Detection via \(source): active=\(snapshot.active) activeProcesses=\(snapshot.activeProcessCount) activeDevices=\(snapshot.activeDeviceCount) device=\(deviceName)"
    }
}

enum CoreAudioError: Error {
    case missingValue(selector: AudioObjectPropertySelector)
    case status(OSStatus, selector: AudioObjectPropertySelector)
}

extension CoreAudioError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingValue(selector):
            return "CoreAudio property \(selector) returned no value"
        case let .status(status, selector):
            return "CoreAudio property \(selector) failed with status \(status)"
        }
    }
}
