// iOS port (Chesly fork, 2026-11): gate G1. In one process, LiveKit's WebRTC makes an offer while
// two ntgcalls instances run the full key exchange and a P2P connection, then carry a sine wave
// both ways for 60 seconds.
import G1Support
import LiveKitWebRTC
import XCTest

final class CoexistenceTests: XCTestCase {
    /// Any 2048-bit modulus serves here: the test needs both ends to agree, not a safe prime.
    private let prime = [UInt8](repeating: 0xFF, count: 256)

    private func randomBytes() -> [UInt8] {
        (0..<256).map { _ in UInt8.random(in: 0...255) }
    }

    private func wait(_ what: String, timeout: TimeInterval, until condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                throw NSError(
                    domain: "g1", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out waiting for \(what)"])
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// LiveKit's half: a peer connection factory, and an offer made while ntgcalls runs.
    private func makeLiveKitOffer() throws {
        XCTAssertTrue(LKRTCInitializeSSL())
        let factory = LKRTCPeerConnectionFactory()
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let connection = try XCTUnwrap(
            factory.peerConnection(with: LKRTCConfiguration(), constraints: constraints, delegate: nil))
        _ = connection.dataChannel(forLabel: "g1", configuration: LKRTCDataChannelConfiguration())
        let offered = expectation(description: "LKRTC offer")
        connection.offer(for: constraints) { description, error in
            XCTAssertNil(error)
            XCTAssertEqual(description?.sdp.contains("m=application"), true)
            offered.fulfill()
        }
        wait(for: [offered], timeout: 20)
        connection.close()
    }

    func testEngineBesideLiveKit() throws {
        print("ntgcalls \(engineVersion())")
        XCTAssertTrue(engineVersion().contains("+ios."))

        let logs = LogStore()
        logs.install()

        let caller = try CallSide(name: "caller")
        let callee = try CallSide(name: "callee")
        caller.peer = callee
        callee.peer = caller

        try caller.prepare()
        try callee.prepare()

        let gaHash = try caller.initExchange(prime: prime, random: randomBytes(), gaHash: nil)
        let gB = try callee.initExchange(prime: prime, random: randomBytes(), gaHash: gaHash)
        let callerAuth = try caller.exchangeKeys(gB, fingerprint: 0)
        let calleeAuth = try callee.exchangeKeys(callerAuth.gAOrB, fingerprint: callerAuth.fingerprint)
        XCTAssertEqual(callerAuth.fingerprint, calleeAuth.fingerprint)

        let callerEmojis = try caller.emojis()
        let calleeEmojis = try callee.emojis()
        print("emojis \(callerEmojis) / \(calleeEmojis)")
        XCTAssertFalse(callerEmojis.isEmpty)
        XCTAssertEqual(callerEmojis, calleeEmojis)
        XCTAssertEqual(callerEmojis.count, 4)

        try caller.connect()
        try callee.connect()

        try makeLiveKitOffer()

        try wait("both ends to connect", timeout: 30) { caller.isConnected && callee.isConnected }
        print("connected")

        caller.startSending(frequency: 440)
        callee.startSending(frequency: 660)

        Thread.sleep(forTimeInterval: 60)

        caller.stopSending()
        callee.stopSending()

        let heardByCaller = caller.received
        let heardByCallee = callee.received
        print("caller heard \(heardByCaller), callee heard \(heardByCallee)")
        XCTAssertGreaterThan(heardByCaller.frames, 1000)
        XCTAssertGreaterThan(heardByCallee.frames, 1000)
        XCTAssertGreaterThan(heardByCaller.peak, 1000)
        XCTAssertGreaterThan(heardByCallee.peak, 1000)

        caller.stop()
        callee.stop()

        let fingerprints = [
            String(callerAuth.fingerprint), String(UInt64(bitPattern: callerAuth.fingerprint)),
        ]
        let lines = logs.snapshot()
        print("\(lines.count) log lines")
        for line in lines {
            for fingerprint in fingerprints {
                XCTAssertFalse(line.contains(fingerprint), "a log line carries the key fingerprint")
            }
        }
    }
}
