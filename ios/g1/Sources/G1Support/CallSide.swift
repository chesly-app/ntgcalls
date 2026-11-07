// iOS port (Chesly fork, 2026-11): one end of a test call, driving the C API the way an app does:
// every engine call on one serial queue, audio as exact 10 ms external frames, signaling handed
// to the other end's queue. Used by gate G1 only.
import Foundation
import ntgcalls

public let sampleRate: UInt32 = 48000
/// 10 ms of 48 kHz mono 16-bit PCM. The engine reads exactly this many bytes of each frame.
public let frameBytes = 960

public func engineVersion() -> String {
    String(cString: ntg_get_version())
}

public func checked(_ result: ntg_result, _ what: String) throws {
    guard result == NTG_OK else {
        let detail = ntg_last_error().map { String(cString: $0) } ?? ""
        throw NSError(
            domain: "ntgcalls", code: Int(result.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "\(what): \(result.rawValue) \(detail)"])
    }
}

/// Everything ntgcalls logs, kept so a test can search it.
public final class LogStore {
    private let lock = NSLock()
    private var lines: [String] = []

    public init() {}

    public func install() {
        ntg_set_log_callback(
            { message, context in
                guard let context, let text = message.message else { return }
                Unmanaged<LogStore>.fromOpaque(context).takeUnretainedValue().add(String(cString: text))
            }, Unmanaged.passUnretained(self).toOpaque())
    }

    private func add(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    public func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

public final class CallSide {
    public let name: String
    public let chat: Int64 = 1
    public let queue: DispatchQueue
    public weak var peer: CallSide?

    private let handle: OpaquePointer
    private let lock = NSLock()
    private var receivedFrames = 0
    private var receivedPeak = 0
    private var state: ntg_connection_state?
    private var stopped = false

    public init(name: String) throws {
        self.name = name
        queue = DispatchQueue(label: "g1.\(name)")
        guard let created = ntg_instance_create() else {
            throw NSError(
                domain: "ntgcalls", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ntg_instance_create answered NULL: is this the stub slice?"])
        }
        handle = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        try checked(
            ntg_on_signaling_data_callback(
                handle,
                { _, _, data, length, context in
                    guard let context, let data else { return }
                    let side = Unmanaged<CallSide>.fromOpaque(context).takeUnretainedValue()
                    side.forwardSignaling(Data(bytes: data, count: length))
                }, context),
            "on_signaling_data")
        try checked(
            ntg_on_connection_change_callback(
                handle,
                { _, _, info, context in
                    guard let context else { return }
                    Unmanaged<CallSide>.fromOpaque(context).takeUnretainedValue().record(info.state)
                }, context),
            "on_connection_change")
        try checked(
            ntg_on_frames_callback(
                handle,
                { _, _, mode, device, frames, count, context in
                    guard let context, let frames, mode == NTG_STREAM_MODE_PLAYBACK,
                        device == NTG_STREAM_DEVICE_MICROPHONE
                    else { return }
                    let side = Unmanaged<CallSide>.fromOpaque(context).takeUnretainedValue()
                    for index in 0..<count {
                        side.record(frame: frames[index])
                    }
                }, context),
            "on_frames")
    }

    deinit {
        ntg_instance_destroy(handle)
    }

    private func forwardSignaling(_ data: Data) {
        guard let peer else { return }
        peer.queue.async {
            data.withUnsafeBytes { bytes in
                _ = ntg_send_signaling_data(
                    peer.handle, peer.chat, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
            }
        }
    }

    private func record(_ newState: ntg_connection_state) {
        lock.lock()
        state = newState
        lock.unlock()
    }

    private func record(frame: ntg_frame) {
        guard let data = frame.data else { return }
        var peak = 0
        var offset = 0
        while offset + 1 < frame.data_len {
            let sample = Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
            peak = max(peak, abs(Int(sample)))
            offset += 2
        }
        lock.lock()
        receivedFrames += 1
        receivedPeak = max(receivedPeak, peak)
        lock.unlock()
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == NTG_CONNECTION_STATE_CONNECTED
    }

    public var received: (frames: Int, peak: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (receivedFrames, receivedPeak)
    }

    private func perform<T>(_ work: () throws -> T) rethrows -> T {
        try queue.sync(execute: work)
    }

    /// Creates the call with external audio both ways, as an app does before the key exchange.
    public func prepare() throws {
        try perform {
            try checked(ntg_create_p2p_call(handle, chat), "create_p2p_call")
            let empty = strdup("")
            defer { free(empty) }
            var audio = ntg_audio_description(
                media_source: NTG_MEDIA_SOURCE_EXTERNAL, sample_rate: sampleRate, channel_count: 1,
                input: empty, keep_open: true)
            try withUnsafeMutablePointer(to: &audio) { pointer in
                let media = ntg_media_description(microphone: pointer, speaker: nil, camera: nil, screen: nil)
                try checked(ntg_set_stream_sources(handle, chat, NTG_STREAM_MODE_CAPTURE, media), "capture sources")
                try checked(ntg_set_stream_sources(handle, chat, NTG_STREAM_MODE_PLAYBACK, media), "playback sources")
            }
        }
    }

    /// The caller passes no hash and gets the hash of g_a; the callee passes it and gets g_b.
    public func initExchange(prime: [UInt8], random: [UInt8], gaHash: [UInt8]?) throws -> [UInt8] {
        try perform {
            var prime = prime
            var random = random
            var out: UnsafeMutablePointer<UInt8>?
            var length = 0
            try prime.withUnsafeMutableBufferPointer { primeBuffer in
                try random.withUnsafeMutableBufferPointer { randomBuffer in
                    let config = ntg_dh_config(
                        g: 3, p: primeBuffer.baseAddress, p_len: primeBuffer.count,
                        random: randomBuffer.baseAddress, random_len: randomBuffer.count)
                    if let gaHash {
                        try gaHash.withUnsafeBufferPointer { hash in
                            try checked(
                                ntg_init_exchange(handle, chat, config, hash.baseAddress, hash.count, &out, &length),
                                "init_exchange")
                        }
                    } else {
                        try checked(ntg_init_exchange(handle, chat, config, nil, 0, &out, &length), "init_exchange")
                    }
                }
            }
            defer { ntg_bytes_free(out) }
            return Array(UnsafeBufferPointer(start: out, count: length))
        }
    }

    public func exchangeKeys(_ gAOrB: [UInt8], fingerprint: Int64) throws -> (fingerprint: Int64, gAOrB: [UInt8]) {
        try perform {
            var auth = ntg_auth_params()
            try gAOrB.withUnsafeBufferPointer { key in
                try checked(
                    ntg_exchange_keys(handle, chat, key.baseAddress, key.count, fingerprint, &auth),
                    "exchange_keys")
            }
            let result = (auth.key_fingerprint, Array(UnsafeBufferPointer(start: auth.g_a_or_b, count: auth.g_a_or_b_len)))
            ntg_bytes_free(auth.g_a_or_b)
            return result
        }
    }

    /// `allowLocal` is the test switch for the iOS filter: two ends on one machine reach each other
    /// only over local addresses, which the filter keeps out of a real call.
    public func connect(allowLocal: Bool) throws {
        try perform {
            var protocolInfo = ntg_protocol()
            try checked(ntg_get_protocol(&protocolInfo), "get_protocol")
            defer { ntg_protocol_free(&protocolInfo) }
            let versions = (0..<protocolInfo.library_versions_len).map {
                UnsafePointer<CChar>(protocolInfo.library_versions[$0])
            }
            let parameters = "{\"network_allow_local_addresses\":\(allowLocal)}"
            try versions.withUnsafeBufferPointer { list in
                try parameters.withCString { json in
                    try checked(
                        ntg_connect_p2p(handle, chat, nil, 0, UnsafeMutablePointer(mutating: list.baseAddress), list.count, true, json),
                        "connect_p2p")
                }
            }
        }
    }

    public func emojis() throws -> String {
        try perform {
            var out: UnsafeMutablePointer<CChar>?
            try checked(ntg_get_emojis_fingerprint(handle, chat, &out), "get_emojis_fingerprint")
            defer { ntg_string_free(out) }
            return out.map { String(cString: $0) } ?? ""
        }
    }

    /// Sends a sine wave as exact 10 ms frames until `stopSending()`, from this side's queue.
    public func startSending(frequency: Double) {
        let period = 0.010
        var phase = 0.0
        let step = 2.0 * Double.pi * frequency / Double(sampleRate)
        var frame = [UInt8](repeating: 0, count: frameBytes)
        var next = Date()
        func tick() {
            lock.lock()
            let done = stopped
            lock.unlock()
            if done { return }
            for index in 0..<(frameBytes / 2) {
                let sample = Int16(sin(phase) * 12000)
                phase += step
                frame[index * 2] = UInt8(truncatingIfNeeded: sample)
                frame[index * 2 + 1] = UInt8(truncatingIfNeeded: sample >> 8)
            }
            let data = ntg_frame_data(
                absolute_capture_timestamp_ms: 0, rotation: NTG_VIDEO_ROTATION_VIDEO_ROTATION_0, width: 0, height: 0)
            frame.withUnsafeBufferPointer { bytes in
                _ = ntg_send_external_frame(
                    handle, chat, NTG_STREAM_DEVICE_MICROPHONE, bytes.baseAddress, bytes.count, data)
            }
            next = next.addingTimeInterval(period)
            queue.asyncAfter(deadline: .now() + max(0, next.timeIntervalSinceNow), execute: tick)
        }
        queue.async(execute: tick)
    }

    public func stopSending() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public func stop() {
        perform { _ = ntg_stop(handle, chat) }
    }
}
