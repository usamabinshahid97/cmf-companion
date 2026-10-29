import Foundation
import Testing
@testable import BudsCore

@Test func crcMatchesModbusCheckVector() {
    #expect(BudsWire.crc(Array("123456789".utf8)) == 0x4B37)
}

@Test func knownBatteryRequest() {
    let bytes = BudsWire.encode(BudsFrame(command: 0xC007, sequence: 1, payload: []))
    #expect(Array(bytes.prefix(8)) == [0x55, 0x60, 0x01, 0x07, 0xC0, 0, 0, 1])
    var parser = BudsFrameParser()
    #expect(parser.feed(bytes) == [BudsFrame(command: 0xC007, sequence: 1, payload: [])])
}

@Test func fragmentedAndCombinedFrames() {
    let a = BudsFrame(command: 0x4007, sequence: 21, payload: [2, 2, 90, 3, 80])
    let b = BudsFrame(command: 0xE003, sequence: 0, payload: [1, 7, 0])
    let bytes = BudsWire.encode(a)
    var parser = BudsFrameParser()
    #expect(parser.feed(Array(bytes.prefix(6))).isEmpty)
    #expect(parser.feed(Array(bytes.dropFirst(6)) + BudsWire.encode(b)) == [a, b])
}

@Test func rejectsCorruptFramesAndResynchronizes() {
    let a = BudsFrame(command: 0x4007, sequence: 1, payload: [1, 2, 50])
    var damaged = BudsWire.encode(a)
    damaged[10] ^= 0x20
    var parser = BudsFrameParser()
    #expect(parser.feed([0, 1, 8] + damaged + BudsWire.encode(a)) == [a])
}

@Test func rejectsOversizedFrameHeader() {
    let a = BudsFrame(command: 0x4050, sequence: 2, payload: [6])
    var parser = BudsFrameParser()
    #expect(parser.feed([0x55, 0x60, 1, 1, 0x40, 0xFF, 0x7F, 0, 0, 0] + BudsWire.encode(a)) == [a])
}

@Test func notificationControlBytes() {
    let a = BudsFrame(command: 0xE003, sequence: 0, payload: [1, 5, 0])
    var bytes = BudsWire.encode(a)
    bytes[1] = 0x20; bytes[2] = 3
    let crc = BudsWire.crc(bytes.dropLast(2))
    bytes[bytes.count - 2] = UInt8(truncatingIfNeeded: crc)
    bytes[bytes.count - 1] = UInt8(crc >> 8)
    var parser = BudsFrameParser()
    #expect(parser.feed(bytes) == [a])
}

@Test func batteryUsesChargingBitAndOmitsUnknownValues() {
    let result = BatteryReading.decode([3, 2, 100, 3, 0xD0, 4, 0xFF])
    #expect(result?[2]?.percent == 100)
    #expect(result?[2]?.charging == false)
    #expect(result?[3]?.percent == 80)
    #expect(result?[3]?.charging == true)
    #expect(result?[4] == nil)
    #expect(BatteryReading.decode([3, 2, 10]) == nil)
}

@Test func b179PresetAndANCCommands() {
    #expect(BudsCommand.equalizer == 0xC050)
    #expect(BudsCommand.setEqualizer == 0xF01D)
    #expect(EQPreset.custom.rawValue == 6)
    #expect(EQPreset.pop.rawValue == 3)
    #expect(NoiseMode.low.payload == [1, 3, 0])
    #expect(NoiseMode.high.payload == [1, 1, 0])
    #expect(NoiseMode.transparency.payload == [1, 7, 0])
}

@Test func customEQRoundTripsWithB179Frequencies() {
    let curve = CustomEQ(bass: -4, mid: 2, treble: 6)
    let bytes = curve.encode()
    #expect(bytes.count == 53)
    #expect(CustomEQ.decode(bytes) == curve)
    func float(_ offset: Int) -> Float {
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(bytes[offset + i]) << (i * 8) }
        return Float(bitPattern: bits)
    }
    #expect(float(1) == -6)
    #expect(float(10) == 980)
    #expect(float(23) == 6900)
    #expect(float(36) == 140)
    #expect(bytes[5] == 1 && bytes[18] == 2 && bytes[31] == 0)
    #expect(CustomEQ.decode([3, 0, 0]) == nil)
}

@Test func customEQRejectsNonfiniteReadbackAndClampsWrites() {
    #expect(CustomEQ.decode(CustomEQ(bass: 50, mid: -50, treble: .nan).encode()) == CustomEQ(bass: 6, mid: -6, treble: 0))
    var bytes = CustomEQ().encode()
    bytes.replaceSubrange(6..<10, with: [0, 0, 0xC0, 0x7F])
    #expect(CustomEQ.decode(bytes) == nil)
}

@Test func gestureMappingsAreCmfNotHeadphoneMappings() {
    let rows = GestureBinding.decode([2, 2, 1, 2, 9, 3, 1, 7, 22])
    #expect(rows?.count == 2)
    #expect(rows?.first?.payload == [1, 2, 1, 2, 9])
    #expect(rows?.first?.title == "Double tap")
    #expect(rows?.last?.title == "Tap & hold")
    #expect(GestureBinding.actionTitle(22) == "ANC ↔ Transparency")
    #expect(GestureBinding.actionTitle(20) == "ANC ↔ Off")
    #expect(GestureBinding.actionTitle(2) == "Play / pause")
    #expect(rows?.first?.allowedActions.contains(18) == false)
    #expect(GestureBinding.decode([2, 2, 1, 2, 9]) == nil)
}

@Test func multipointNamesAndAddressByteOrder() {
    let name = Array("Usama’s Mac".utf8)
    let bytes: [UInt8] = [0, 2, 1, 0x11, 1, 2, 3, 4, 5, 6, UInt8(name.count)] + name
    let devices = MultipointDevice.decodePage(bytes)
    #expect(devices?.count == 1)
    #expect(devices?.first?.name == "Usama’s Mac")
    #expect(devices?.first?.isThisMac == true)
    #expect(devices?.first?.connected == true)
    #expect(devices?.first?.payload(connect: false) == [0, 1, 2, 3, 4, 5, 6])
    #expect(MultipointDevice.decodePage(Array(bytes.dropLast())) == nil)
    #expect(MultipointDevice.decodePage([0, 0, 0]) == [])
}

@Test func featureLookupDoesNotAssumeFirstRowIsInEar() {
    #expect(FeatureFlags.inEar([3, 2, 1, 1, 0, 7, 1]) == false)
    #expect(FeatureFlags.inEar([2, 2, 0, 1, 1]) == true)
    #expect(FeatureFlags.inEar([1, 2, 1]) == nil)
    #expect(FeatureFlags.inEar([2, 1, 1]) == nil)
}
