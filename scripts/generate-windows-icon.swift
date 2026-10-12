import Foundation

// Windows Vista+ supports PNG payloads in ICO files, including full alpha.
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate-windows-icon.swift <iconset> <output.ico>\n", stderr)
    exit(1)
}
let source = URL(fileURLWithPath: arguments[1], isDirectory: true)
let sizesAndFiles = [(16, "icon_16x16.png"), (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"), (128, "icon_128x128.png"), (256, "icon_256x256.png")]

func appendUInt16(_ value: UInt16, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}
func appendUInt32(_ value: UInt32, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

do {
    let payloads = try sizesAndFiles.map { try Data(contentsOf: source.appendingPathComponent($0.1)) }
    var result = Data()
    appendUInt16(0, to: &result)
    appendUInt16(1, to: &result)
    appendUInt16(UInt16(payloads.count), to: &result)
    var offset = UInt32(6 + payloads.count * 16)
    for (index, payload) in payloads.enumerated() {
        let dimension = sizesAndFiles[index].0
        let byte = dimension == 256 ? UInt8(0) : UInt8(dimension)
        result.append(contentsOf: [byte, byte, 0, 0])
        appendUInt16(1, to: &result)
        appendUInt16(32, to: &result)
        appendUInt32(UInt32(payload.count), to: &result)
        appendUInt32(offset, to: &result)
        offset += UInt32(payload.count)
    }
    for payload in payloads { result.append(payload) }
    try result.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
} catch {
    fputs("Cannot create Windows icon: \(error)\n", stderr)
    exit(1)
}
