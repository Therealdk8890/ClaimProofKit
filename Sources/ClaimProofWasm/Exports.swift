// Copyright 2026 Daniel Kissel
// SPDX-License-Identifier: BUSL-1.1

// A C-ABI WebAssembly reactor wrapper over ClaimProofBridge, so a browser (an
// Office add-in taskpane) can drive verification with no companion process. The
// bridge already exposes a JSON-in/JSON-out boundary; this layer only adds the
// pointer+length marshalling a wasm host needs, plus a malloc/free pair the host
// uses to hand bytes in and reclaim bytes out.
//
// This is an integration adapter under PRODUCT_BOUNDARY.md — it contains no
// ClaimProofCloud-only capability. Build it with the WebAssembly SDK in reactor
// exec-model:
//   swift build -c release --swift-sdk <wasm-sdk-id> --product ClaimProofWasm \
//     -Xswiftc -Xclang-linker -Xswiftc -mexec-model=reactor
//
// The exports live behind `#if arch(wasm32)` so native builds, `swift test`,
// and CI are unaffected; on those platforms the target compiles to a stub whose
// binary is never run (the target exists only to be compiled to wasm).

import ClaimProofBridge

/// The C-ABI contract version, exported as `cpk_abi_version`. Bump on ANY
/// breaking change to this surface: an export added is compatible (no bump
/// needed), but renaming/removing an export, changing a signature, changing
/// the memory-ownership rules, or an incompatible change to the bridge
/// Request/Response JSON schema requires a bump. A host should read this
/// before anything else and refuse to drive a module it does not recognize —
/// wasm binaries and their JS wrappers ship on different cadences (caches,
/// CDNs, side-loaded manifests), and without this check a skew surfaces as
/// confusing `invalidRequest` errors instead of a clean version mismatch.
///
/// History: 1 = initial surface (cpk_malloc, cpk_free, cpk_verify,
/// cpk_passage_fingerprint, cpk_claim_fingerprint).
let currentABIVersion: Int32 = 1

#if arch(wasm32)

/// Returns the C-ABI contract version (see `currentABIVersion`). Takes no
/// arguments and allocates nothing, so it is safe to call before any other
/// export and cannot fail.
@_expose(wasm, "cpk_abi_version")
@_cdecl("cpk_abi_version")
public func cpk_abi_version() -> Int32 {
    currentABIVersion
}

/// Allocates `size` bytes of linear memory and returns the pointer. The host
/// writes request bytes here before calling `cpk_verify`, and frees the result
/// buffer here after reading it. `size` is clamped to at least 1 so a zero-byte
/// request still yields a valid, freeable pointer.
@_expose(wasm, "cpk_malloc")
@_cdecl("cpk_malloc")
public func cpk_malloc(_ size: Int) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer.allocate(byteCount: max(size, 1), alignment: 1)
}

/// Frees a buffer previously returned by `cpk_malloc` or `cpk_verify`. `size` is
/// accepted for symmetry with sized allocators and is unused here.
@_expose(wasm, "cpk_free")
@_cdecl("cpk_free")
public func cpk_free(_ pointer: UnsafeMutableRawPointer, _ size: Int) {
    pointer.deallocate()
}

/// Runs deterministic verification over a UTF-8 JSON request and returns a
/// pointer to a freshly allocated UTF-8 JSON response, writing the response
/// length (in bytes) to `outLen`. The host reads `memory[result ..< result +
/// outLen]`, then MUST call `cpk_free(result, outLen)`.
///
/// The request/response shapes are `ClaimProofBridge.Request`/`Response`;
/// malformed input returns a structured `ErrorResponse` JSON object rather than
/// trapping across the boundary.
@_expose(wasm, "cpk_verify")
@_cdecl("cpk_verify")
public func cpk_verify(
    _ requestPointer: UnsafePointer<UInt8>,
    _ requestLength: Int,
    _ outLen: UnsafeMutablePointer<Int>
) -> UnsafeMutablePointer<UInt8> {
    let request = String(
        decoding: UnsafeBufferPointer(start: requestPointer, count: requestLength),
        as: UTF8.self
    )
    return copyToHost(ClaimProofBridge.verify(requestJSON: request), outLen)
}

/// SHA-256 evidence fingerprint (spec §5) of a UTF-8 string, as lowercase-hex
/// JSON-free plain text. Returns a host-owned buffer; free with `cpk_free`.
///
/// PRECONDITION: the input must be valid UTF-8. Invalid sequences are repaired
/// to U+FFFD before hashing (Swift's lossy decode), so the returned hash is
/// the identity of the repaired text, not of the raw bytes — the same
/// interpretation `cpk_verify` applies when those bytes arrive as passage
/// text, but NOT reproducible from the original bytes by an external SHA-256.
/// Hosts using `TextEncoder` never hit this path (it cannot emit invalid
/// UTF-8; lone surrogates become U+FFFD at encode time, on the host side).
@_expose(wasm, "cpk_passage_fingerprint")
@_cdecl("cpk_passage_fingerprint")
public func cpk_passage_fingerprint(
    _ textPointer: UnsafePointer<UInt8>,
    _ textLength: Int,
    _ outLen: UnsafeMutablePointer<Int>
) -> UnsafeMutablePointer<UInt8> {
    let text = String(decoding: UnsafeBufferPointer(start: textPointer, count: textLength), as: UTF8.self)
    return copyToHost(ClaimProofBridge.passageFingerprint(text: text), outLen)
}

/// FNV-1a 64-bit claim fingerprint (spec §1: case-folded input, unpadded
/// lowercase hex) of a UTF-8 string, as JSON-free plain text. Returns a
/// host-owned buffer; free with `cpk_free`. Exported so hosts that cache or
/// diff claim identity across edits never reimplement a frozen spec
/// algorithm. Same UTF-8 precondition as `cpk_passage_fingerprint`.
@_expose(wasm, "cpk_claim_fingerprint")
@_cdecl("cpk_claim_fingerprint")
public func cpk_claim_fingerprint(
    _ textPointer: UnsafePointer<UInt8>,
    _ textLength: Int,
    _ outLen: UnsafeMutablePointer<Int>
) -> UnsafeMutablePointer<UInt8> {
    let text = String(decoding: UnsafeBufferPointer(start: textPointer, count: textLength), as: UTF8.self)
    return copyToHost(ClaimProofBridge.claimFingerprint(text: text), outLen)
}

/// Copies a Swift string's UTF-8 bytes into a host-freeable buffer and records
/// its length. Shared by every string-returning export. The empty-string guard
/// matters even though current exports always return non-empty text: for an
/// empty array `withUnsafeBufferPointer` may pass a nil base address, and the
/// force-unwrap would trap the instance.
private func copyToHost(_ string: String, _ outLen: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8> {
    let bytes = Array(string.utf8)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(bytes.count, 1))
    if !bytes.isEmpty {
        bytes.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: bytes.count) }
    }
    outLen.pointee = bytes.count
    return buffer
}

#else

// Native / non-wasm builds: the wasm exports don't apply, but an executable
// target still needs an entry point to link. This binary is never executed;
// it exists so the package builds and tests cleanly on developer machines and
// CI while the same sources compile to a wasm reactor under the SDK.
@main
enum ClaimProofWasmNativeStub {
    static func main() {}
}

#endif
