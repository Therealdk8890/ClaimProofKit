// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: Apache-2.0
//
// Verifies that a WebAssembly module's EXPORT SECTION contains every function
// name passed on the command line. Grepping the raw binary is not sound here:
// release builds carry DWARF custom sections, and .debug_str stores every C
// symbol name NUL-terminated — so a function whose @_expose was dropped (but
// whose @_cdecl symbol remains) still matches a `name\0` substring search.
// Only decoding section id 7 proves the module actually exports the function.
//
//   swift scripts/check-wasm-exports.swift <module.wasm> <name> [<name> ...]
//
// Exit 0: all names exported as functions. Exit 1: at least one missing.
// Exit 2: unreadable or malformed module (never treated as "missing").

import Foundation

struct ParseError: Error, CustomStringConvertible {
    let description: String
}

struct Parser {
    let bytes: [UInt8]
    var offset = 0

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw ParseError(description: "unexpected end of module at offset \(offset)") }
        defer { offset += 1 }
        return bytes[offset]
    }

    // Unsigned LEB128, capped at 32 bits (all section/vector sizes in core wasm).
    mutating func uleb32() throws -> Int {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try byte()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
            guard shift < 35 else { throw ParseError(description: "uleb128 too long at offset \(offset)") }
        }
        guard result <= UInt64(UInt32.max) else { throw ParseError(description: "uleb128 exceeds u32 at offset \(offset)") }
        return Int(result)
    }

    mutating func bytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, offset + count <= bytes.count else {
            throw ParseError(description: "unexpected end of module reading \(count) bytes at offset \(offset)")
        }
        defer { offset += count }
        return bytes[offset ..< offset + count]
    }
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: swift check-wasm-exports.swift <module.wasm> <export-name> [<export-name> ...]", code: 64)
}
let modulePath = arguments[1]
let expected = Array(arguments[2...])

guard let data = FileManager.default.contents(atPath: modulePath) else {
    fail("cannot read module: \(modulePath)", code: 2)
}

do {
    var parser = Parser(bytes: [UInt8](data))
    guard try parser.bytes(4).elementsEqual([0x00, 0x61, 0x73, 0x6D]) else {
        throw ParseError(description: "not a wasm module (bad magic)")
    }
    guard try parser.bytes(4).elementsEqual([0x01, 0x00, 0x00, 0x00]) else {
        throw ParseError(description: "unsupported wasm binary version")
    }

    // Export names are unique module-wide by validation; kind 0x00 = function.
    var functionExports = Set<String>()
    var sawExportSection = false
    while parser.offset < parser.bytes.count {
        let id = try parser.byte()
        let size = try parser.uleb32()
        if id != 7 {
            _ = try parser.bytes(size)
            continue
        }
        sawExportSection = true
        let end = parser.offset + size
        let count = try parser.uleb32()
        for _ in 0 ..< count {
            let nameLength = try parser.uleb32()
            let name = String(decoding: try parser.bytes(nameLength), as: UTF8.self)
            let kind = try parser.byte()
            _ = try parser.uleb32() // index
            if kind == 0x00 { functionExports.insert(name) }
        }
        guard parser.offset == end else {
            throw ParseError(description: "export section size mismatch (\(parser.offset) != \(end))")
        }
    }
    guard sawExportSection else { throw ParseError(description: "module has no export section") }

    var missing = [String]()
    for name in expected {
        if functionExports.contains(name) {
            print("export present: \(name)")
        } else {
            missing.append(name)
        }
    }
    if !missing.isEmpty {
        fail("missing function export(s): \(missing.joined(separator: ", "))", code: 1)
    }
} catch {
    fail("malformed module \(modulePath): \(error)", code: 2)
}
