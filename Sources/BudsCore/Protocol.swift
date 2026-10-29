import Foundation

// Nothing / CMF NT LINK. Framing informed by Nothing X Mac (MIT); see THIRD_PARTY.md.
public enum BudsCommand {
    public static let protocolVersion: UInt16 = 0xC001
    public static let model: UInt16 = 0xC01C
    public static let battery: UInt16 = 0xC007
    public static let firmware: UInt16 = 0xC042
    public static let noise: UInt16 = 0xC01E
    public static let setNoise: UInt16 = 0xF00F
    // B179 uses listening mode, not the Nothing Ear EQ preset command.
    public static let equalizer: UInt16 = 0xC050
    public static let setEqualizer: UInt16 = 0xF01D
    public static let customEQ: UInt16 = 0xC044
    public static let setCustomEQ: UInt16 = 0xF041
    public static let bass: UInt16 = 0xC04E
    public static let setBass: UInt16 = 0xF051
    public static let spatial: UInt16 = 0xC04F
    public static let setSpatial: UInt16 = 0xF052
    public static let latency: UInt16 = 0xC041
    public static let setLatency: UInt16 = 0xF040
    public static let features: UInt16 = 0xC00E
    public static let setFeature: UInt16 = 0xF004
    public static let dual: UInt16 = 0xC027
    public static let setDual: UInt16 = 0xF01A
    public static let devices: UInt16 = 0xC028
    public static let setDevice: UInt16 = 0xF01B
    public static let gestures: UInt16 = 0xC018
    public static let setGesture: UInt16 = 0xF003
    public static let ring: UInt16 = 0xF002
    public static let fitTest: UInt16 = 0xF014
}

public struct BudsFrame: Equatable, Sendable {
    public let command: UInt16
    public let sequence: UInt8
    public let payload: [UInt8]
    public init(command: UInt16, sequence: UInt8, payload: [UInt8]) {
        self.command = command; self.sequence = sequence; self.payload = payload
    }
}

public enum BudsWire {
    public static let serviceUUID: [UInt8] = [0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
                                              0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB]
    public static func crc(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var result: UInt16 = 0xFFFF
        for byte in bytes {
            result ^= UInt16(byte)
            for _ in 0..<8 { result = result & 1 == 1 ? (result >> 1) ^ 0xA001 : result >> 1 }
        }
        return result
    }
    public static func encode(_ frame: BudsFrame) -> [UInt8] {
        precondition(frame.payload.count <= 1024)
        var bytes: [UInt8] = [0x55, 0x60, 0x01, UInt8(truncatingIfNeeded: frame.command),
                             UInt8(frame.command >> 8), UInt8(truncatingIfNeeded: frame.payload.count),
                             UInt8(frame.payload.count >> 8), frame.sequence] + frame.payload
        let checksum = crc(bytes)
        bytes += [UInt8(truncatingIfNeeded: checksum), UInt8(checksum >> 8)]
        return bytes
    }
}

public struct BudsFrameParser {
    private var buffer: [UInt8] = []
    public init() {}
    public mutating func reset() { buffer.removeAll() }
    public mutating func feed(_ bytes: [UInt8]) -> [BudsFrame] {
        buffer += bytes
        var frames: [BudsFrame] = []
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0x55) else { buffer.removeAll(); break }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 10 else { break }
            guard buffer[1] & 0x20 != 0, [0x01, 0x03].contains(buffer[2]) else {
                buffer.removeFirst(); continue
            }
            let count = Int(buffer[5]) | Int(buffer[6]) << 8
            guard count <= 1024 else { buffer.removeFirst(); continue }
            let size = count + 10
            guard buffer.count >= size else { break }
            let checksum = UInt16(buffer[size - 2]) | UInt16(buffer[size - 1]) << 8
            guard BudsWire.crc(buffer.prefix(size - 2)) == checksum else {
                buffer.removeFirst(); continue
            }
            frames.append(BudsFrame(command: UInt16(buffer[3]) | UInt16(buffer[4]) << 8,
                                    sequence: buffer[7], payload: Array(buffer[8..<(size - 2)])))
            buffer.removeFirst(size)
        }
        return frames
    }
}

public enum NoiseMode: UInt8, CaseIterable, Identifiable, Sendable {
    case high = 1, medium = 2, low = 3, adaptive = 4, off = 5, transparency = 7
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .adaptive: "Adaptive"
        case .off: "Off"
        case .transparency: "Transparency"
        }
    }
    public var isANC: Bool { rawValue <= 4 }
    public var payload: [UInt8] { [1, rawValue, 0] }
}

public enum EQPreset: UInt8, CaseIterable, Identifiable, Sendable {
    case dirac = 0, rock = 1, electronic = 2, pop = 3, vocals = 4, classical = 5, custom = 6
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .dirac: "Dirac Opteo"
        case .rock: "Rock"
        case .electronic: "Electronic"
        case .pop: "Pop"
        case .vocals: "Enhance vocals"
        case .classical: "Classical"
        case .custom: "Custom"
        }
    }
}

public struct BatteryReading: Equatable, Sendable {
    public let percent: Int
    public let charging: Bool
    public static func decode(_ payload: [UInt8]) -> [UInt8: BatteryReading]? {
        guard let count = payload.first, payload.count >= 1 + Int(count) * 2 else { return nil }
        var readings: [UInt8: BatteryReading] = [:]
        for index in 0..<Int(count) {
            let value = payload[2 + index * 2]
            let percent = Int(value & 0x7F)
            if percent <= 100 {
                readings[payload[1 + index * 2]] = BatteryReading(percent: percent, charging: value & 0x80 != 0)
            }
        }
        return readings
    }
}

// B179: three IIR filters at 140 / 980 / 6900 Hz, distinct from 8-band Nothing EQ.
public struct CustomEQ: Equatable, Sendable {
    public var bass: Float
    public var mid: Float
    public var treble: Float
    public init(bass: Float = 0, mid: Float = 0, treble: Float = 0) {
        self.bass = bass; self.mid = mid; self.treble = treble
    }
    private static func bytes(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
    }
    private static func float(_ bytes: [UInt8], _ offset: Int) -> Float {
        var bits: UInt32 = 0
        for index in 0..<4 { bits |= UInt32(bytes[offset + index]) << (index * 8) }
        return Float(bitPattern: bits)
    }
    public func encode() -> [UInt8] {
        let gains = [mid, treble, bass].map { min(6, max(-6, $0.isFinite ? $0 : 0)) }
        var bytes: [UInt8] = [3] + Self.bytes(-max(0, gains.max() ?? 0))
        let filters: [(UInt8, Float, Float)] = [(1, 980, 0.7), (2, 6900, 1), (0, 140, 0.8)]
        for (index, filter) in filters.enumerated() {
            bytes += [filter.0] + Self.bytes(gains[index]) + Self.bytes(filter.1) + Self.bytes(filter.2)
        }
        return bytes + Array(repeating: 0, count: 9)
    }
    public static func decode(_ bytes: [UInt8]) -> CustomEQ? {
        guard bytes.count >= 44, bytes[0] == 3 else { return nil }
        let gains = [float(bytes, 6), float(bytes, 19), float(bytes, 32)]
        guard gains.allSatisfy({ $0.isFinite && (-6...6).contains($0) }) else { return nil }
        return CustomEQ(bass: gains[2], mid: gains[0], treble: gains[1])
    }
}

public struct GestureBinding: Identifiable, Equatable, Sendable {
    public var side: UInt8
    public var button: UInt8
    public var gesture: UInt8
    public var action: UInt8
    public var id: Int { Int(side) << 16 | Int(button) << 8 | Int(gesture) }
    public var payload: [UInt8] { [1, side, button, gesture, action] }
    public var title: String {
        switch gesture {
        case 2: "Double tap"
        case 3: "Triple tap"
        case 7: "Tap & hold"
        case 9: "Double tap & hold"
        default: "Gesture \(gesture)"
        }
    }
    public var allowedActions: [UInt8] {
        switch gesture {
        case 2: [2, 8, 9, 11, 1]
        case 3: [8, 9, 11, 1]
        case 7: [10, 20, 21, 22, 11, 1]
        case 9: [18, 19, 11, 1]
        default: []
        }
    }
    public static func actionTitle(_ action: UInt8) -> String {
        switch action {
        case 1: "No action"
        case 2: "Play / pause"
        case 8: "Previous track"
        case 9: "Next track"
        case 10: "ANC ↔ Transparency ↔ Off"
        case 20: "ANC ↔ Off"
        case 21: "Transparency ↔ Off"
        case 22: "ANC ↔ Transparency"
        case 11: "Voice assistant"
        case 18: "Volume up"
        case 19: "Volume down"
        case 31: "News (Nothing phone)"
        default: "Action \(action)"
        }
    }
    public static func decode(_ bytes: [UInt8]) -> [GestureBinding]? {
        guard let count = bytes.first, bytes.count >= 1 + Int(count) * 4 else { return nil }
        return (0..<Int(count)).compactMap { index in
            let offset = 1 + index * 4
            guard [2, 3].contains(bytes[offset]), bytes[offset + 1] == 1,
                  [2, 3, 7, 9].contains(bytes[offset + 2]) else { return nil }
            return GestureBinding(side: bytes[offset], button: bytes[offset + 1],
                                  gesture: bytes[offset + 2], action: bytes[offset + 3])
        }
    }
}

public struct MultipointDevice: Identifiable, Equatable, Sendable {
    public let address: [UInt8]
    public let name: String
    public var connected: Bool
    public let isThisMac: Bool
    public var id: String { address.map { String(format: "%02X", $0) }.joined() }
    public func payload(connect: Bool) -> [UInt8] { [connect ? 1 : 0] + address }
    public static func decodePage(_ bytes: [UInt8]) -> [MultipointDevice]? {
        guard bytes.count >= 3 else { return nil }
        var devices: [MultipointDevice] = []
        var offset = 3
        for _ in 0..<Int(bytes[2]) {
            guard offset + 8 <= bytes.count else { return nil }
            let nameLength = Int(bytes[offset + 7] & 0x7F)
            guard offset + 8 + nameLength <= bytes.count else { return nil }
            let name = String(decoding: bytes[(offset + 8)..<(offset + 8 + nameLength)], as: UTF8.self)
            devices.append(MultipointDevice(address: Array(bytes[(offset + 1)..<(offset + 7)]), name: name,
                                            connected: bytes[offset] & 0x0F != 0,
                                            isThisMac: bytes[offset] & 0xF0 != 0))
            offset += 8 + nameLength
        }
        return devices
    }
}

public enum FeatureFlags {
    public static func inEar(_ bytes: [UInt8]) -> Bool? {
        guard let count = bytes.first, bytes.count >= 1 + Int(count) * 2 else { return nil }
        for index in 0..<Int(count) where bytes[1 + index * 2] == 1 {
            let flag = bytes[2 + index * 2]
            return flag <= 1 ? flag == 1 : nil
        }
        return nil
    }
}
