#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: generate-icns.swift <1024x1024.png> <output.icns>")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pngData = try Data(contentsOf: sourceURL)
let iconChunkLength = 8 + pngData.count
let totalLength = 8 + 16 + iconChunkLength

guard iconChunkLength <= Int(UInt32.max), totalLength <= Int(UInt32.max) else {
    fatalError("Icon data is too large for the ICNS format")
}

func appendFourCC(_ value: String, to data: inout Data) {
    let bytes = Array(value.utf8)
    precondition(bytes.count == 4)
    data.append(contentsOf: bytes)
}

func appendUInt32(_ value: Int, to data: inout Data) {
    var bigEndianValue = UInt32(value).bigEndian
    withUnsafeBytes(of: &bigEndianValue) { data.append(contentsOf: $0) }
}

var output = Data(capacity: totalLength)
appendFourCC("icns", to: &output)
appendUInt32(totalLength, to: &output)
appendFourCC("TOC ", to: &output)
appendUInt32(16, to: &output)
appendFourCC("ic10", to: &output)
appendUInt32(iconChunkLength, to: &output)
appendFourCC("ic10", to: &output)
appendUInt32(iconChunkLength, to: &output)
output.append(pngData)

try output.write(to: outputURL, options: .atomic)
