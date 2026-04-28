import Darwin
import Foundation
import Testing
@testable import petOS

struct ReactionServerTests {
    @Test
    func reactionRequestValidationRejectsInvalidBodies() {
        #expect(ReactionRequestValidator.validate(NSNull()).failure == .bodyMustBeJSONObject)
        #expect(ReactionRequestValidator.validate([:]).failure == .missingType)
        #expect(ReactionRequestValidator.validate(["type": "sparkle", "priority": "high"]).failure == .invalidPriority)
        #expect(ReactionRequestValidator.validate(["type": "sparkle", "payload": "wrong"]).failure == .invalidPayload)
    }

    @Test
    func reactionServerAcceptsValidPostPayload() async throws {
        let collector = EventCollector()
        let server = ReactionServer(port: 0) { event in
            Task {
                await collector.append(event)
            }
        }
        try server.start()
        defer { server.stop() }

        let response = try sendRawReactionRequest(
            port: server.boundPort,
            body: #"{"type":"sparkle_clap","priority":90,"payload":{"source":"test","nested":{"ok":true}}}"#
        )
        try? await Task.sleep(for: .milliseconds(50))

        let payload = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(response.statusCode == 202)
        #expect(payload["ok"] as? Bool == true)
        #expect(await collector.firstType == "sparkle_clap")
    }

    @Test
    func reactionServerRejectsInvalidJSON() async throws {
        let server = ReactionServer(port: 0) { _ in }
        try server.start()
        defer { server.stop() }

        let response = try sendRawReactionRequest(port: server.boundPort, body: "{")
        #expect(response.statusCode == 400)
    }

    @Test
    func reactionServerRejectsInvalidBody() async throws {
        let server = ReactionServer(port: 0) { _ in }
        try server.start()
        defer { server.stop() }

        let response = try sendRawReactionRequest(port: server.boundPort, body: "[]")
        #expect(response.statusCode == 400)
    }
}

private extension Result where Failure == ReactionRequestValidationError {
    var failure: Failure? {
        if case let .failure(error) = self {
            return error
        }

        return nil
    }
}

private actor EventCollector {
    private var events: [PetEvent] = []

    func append(_ event: PetEvent) {
        events.append(event)
    }

    var firstType: String? {
        events.first?.type
    }
}

private struct RawHTTPResponse {
    var statusCode: Int
    var body: Data
}

private func sendRawReactionRequest(port: UInt16, body: String) throws -> RawHTTPResponse {
    let socketDescriptor = Darwin.socket(AF_INET, Int32(SOCK_STREAM), 0)
    guard socketDescriptor >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    defer { Darwin.close(socketDescriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
            Darwin.connect(socketDescriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
        }
    }
    guard connectResult == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    let request = """
    POST /reaction HTTP/1.1\r
    Host: 127.0.0.1\r
    Content-Type: application/json\r
    Content-Length: \(body.utf8.count)\r
    Connection: close\r
    \r
    \(body)
    """
    let requestData = Data(request.utf8)
    _ = requestData.withUnsafeBytes { buffer in
        Darwin.send(socketDescriptor, buffer.baseAddress, requestData.count, 0)
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let bytesRead = Darwin.recv(socketDescriptor, &buffer, buffer.count, 0)
        if bytesRead > 0 {
            responseData.append(contentsOf: buffer[0 ..< bytesRead])
        } else {
            break
        }
    }

    guard
        let separatorRange = responseData.range(of: Data("\r\n\r\n".utf8)),
        let headerText = String(data: responseData[..<separatorRange.lowerBound], encoding: .utf8)
    else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO))
    }

    let statusCode = Int(headerText.components(separatedBy: " ").dropFirst().first ?? "") ?? 0
    return RawHTTPResponse(statusCode: statusCode, body: Data(responseData[separatorRange.upperBound...]))
}
