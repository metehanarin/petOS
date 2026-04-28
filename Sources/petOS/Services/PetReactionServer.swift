import Darwin
import Foundation

struct ReactionRequest: Equatable {
    var type: String
    var priority: Int
    var payload: [String: PetJSONValue]
}

enum ReactionRequestValidationError: LocalizedError, Equatable {
    case invalidJSON
    case bodyMustBeJSONObject
    case missingType
    case invalidPriority
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON."
        case .bodyMustBeJSONObject:
            return "Body must be a JSON object."
        case .missingType:
            return "Field \"type\" is required."
        case .invalidPriority:
            return "Field \"priority\" must be numeric when provided."
        case .invalidPayload:
            return "Field \"payload\" must be an object when provided."
        }
    }
}

enum ReactionRequestValidator {
    static func validate(_ object: Any) -> Result<ReactionRequest, ReactionRequestValidationError> {
        guard let dictionary = object as? [String: Any] else {
            return .failure(.bodyMustBeJSONObject)
        }

        guard
            let rawType = dictionary["type"] as? String,
            !rawType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .failure(.missingType)
        }

        let priority: Int
        if let priorityValue = dictionary["priority"] {
            guard let parsedPriority = parsePriority(priorityValue) else {
                return .failure(.invalidPriority)
            }
            priority = parsedPriority
        } else {
            priority = 50
        }

        let payload: [String: PetJSONValue]
        if let payloadValue = dictionary["payload"] {
            guard let payloadObject = payloadValue as? [String: Any] else {
                return .failure(.invalidPayload)
            }

            var normalizedPayload: [String: PetJSONValue] = [:]
            for (key, value) in payloadObject {
                guard let normalizedValue = normalizeJSONValue(value) else {
                    return .failure(.invalidPayload)
                }
                normalizedPayload[key] = normalizedValue
            }
            payload = normalizedPayload
        } else {
            payload = [:]
        }

        return .success(
            ReactionRequest(
                type: rawType.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: priority,
                payload: payload
            )
        )
    }

    private static func parsePriority(_ value: Any) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            guard double.rounded(.towardZero) == double else {
                return nil
            }
            return Int(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.intValue
        default:
            return nil
        }
    }

    private static func normalizeJSONValue(_ value: Any) -> PetJSONValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .number(Double(int))
        case let double as Double:
            return .number(double)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        case let array as [Any]:
            let normalized = array.compactMap(normalizeJSONValue)
            return normalized.count == array.count ? .array(normalized) : nil
        case let object as [String: Any]:
            var normalized: [String: PetJSONValue] = [:]
            for (key, nestedValue) in object {
                guard let jsonValue = normalizeJSONValue(nestedValue) else {
                    return nil
                }
                normalized[key] = jsonValue
            }
            return .object(normalized)
        case is NSNull:
            return .null
        default:
            return nil
        }
    }
}

enum ReactionServerError: LocalizedError {
    case socketCreationFailed(String)
    case bindFailed(String)
    case listenFailed(String)

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(message):
            return "Socket creation failed: \(message)"
        case let .bindFailed(message):
            return "Bind failed: \(message)"
        case let .listenFailed(message):
            return "Listen failed: \(message)"
        }
    }
}

final class ReactionServer {
    private let requestedPort: UInt16
    private let host: String
    private let queue: DispatchQueue
    private let onAcceptedEvent: (PetEvent) -> Void

    private var listenSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private(set) var boundPort: UInt16

    init(
        port: UInt16 = AppConstants.reactionServerPort,
        host: String = "127.0.0.1",
        onAcceptedEvent: @escaping (PetEvent) -> Void
    ) {
        requestedPort = port
        self.host = host
        boundPort = port
        queue = DispatchQueue(label: "petOS.ReactionServer")
        self.onAcceptedEvent = onAcceptedEvent
    }

    func start() throws {
        guard acceptSource == nil else {
            return
        }

        let socketDescriptor = Darwin.socket(AF_INET, Int32(SOCK_STREAM), 0)
        guard socketDescriptor >= 0 else {
            throw ReactionServerError.socketCreationFailed(String(cString: strerror(errno)))
        }

        var reuseAddress: Int32 = 1
        setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout.size(ofValue: reuseAddress))
        )

        var flags = fcntl(socketDescriptor, F_GETFL, 0)
        if flags >= 0 {
            flags |= O_NONBLOCK
            _ = fcntl(socketDescriptor, F_SETFL, flags)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        inet_pton(AF_INET, host, &address.sin_addr)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                Darwin.bind(socketDescriptor, reboundPointer, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }

        guard bindResult == 0 else {
            Darwin.close(socketDescriptor)
            throw ReactionServerError.bindFailed(String(cString: strerror(errno)))
        }

        guard Darwin.listen(socketDescriptor, SOMAXCONN) == 0 else {
            Darwin.close(socketDescriptor)
            throw ReactionServerError.listenFailed(String(cString: strerror(errno)))
        }

        listenSocket = socketDescriptor
        boundPort = resolvedPort(for: socketDescriptor)

        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: queue)
        acceptSource.setEventHandler { [weak self] in
            self?.acceptConnections()
        }
        acceptSource.setCancelHandler {
            Darwin.close(socketDescriptor)
        }
        self.acceptSource = acceptSource
        acceptSource.resume()
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenSocket = -1
    }

    private func acceptConnections() {
        while true {
            let clientSocket = Darwin.accept(listenSocket, nil, nil)
            if clientSocket < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    return
                }
                return
            }

            handleClient(clientSocket)
        }
    }

    private func handleClient(_ clientSocket: Int32) {
        defer {
            Darwin.close(clientSocket)
        }

        do {
            let requestData = try readRequestData(from: clientSocket)
            let response = handleRequestData(requestData)
            try writeResponse(response, to: clientSocket)
        } catch {
            let response = makeJSONResponse(
                status: 400,
                payload: FailureResponse(ok: false, error: error.localizedDescription)
            )
            try? writeResponse(response, to: clientSocket)
        }
    }

    private func readRequestData(from clientSocket: Int32) throws -> Data {
        var requestData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(2)

        while true {
            let bytesRead = Darwin.recv(clientSocket, &buffer, buffer.count, 0)
            if bytesRead > 0 {
                requestData.append(contentsOf: buffer[0 ..< bytesRead])
                if HTTPRequest.isComplete(requestData) {
                    return requestData
                }
            } else if bytesRead == 0 {
                return requestData
            } else if errno == EINTR {
                continue
            } else if errno == EWOULDBLOCK || errno == EAGAIN {
                if HTTPRequest.isComplete(requestData) {
                    return requestData
                }
                guard Date() < deadline else {
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(ETIMEDOUT),
                        userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for request body."]
                    )
                }
                usleep(1_000)
            } else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
                )
            }
        }
    }

    private func handleRequestData(_ requestData: Data) -> Data {
        guard let request = HTTPRequest.parse(requestData) else {
            return makeJSONResponse(
                status: 400,
                payload: FailureResponse(ok: false, error: ReactionRequestValidationError.invalidJSON.localizedDescription)
            )
        }

        guard request.method == "POST", request.path == "/reaction" else {
            return makeJSONResponse(status: 404, payload: BasicResponse(ok: false))
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: request.body)
        } catch {
            return makeJSONResponse(
                status: 400,
                payload: FailureResponse(ok: false, error: ReactionRequestValidationError.invalidJSON.localizedDescription)
            )
        }

        switch ReactionRequestValidator.validate(jsonObject) {
        case let .success(validRequest):
            let event = PetEvent(
                type: validRequest.type,
                priority: validRequest.priority,
                payload: validRequest.payload
            )
            onAcceptedEvent(event)
            return makeJSONResponse(status: 202, payload: AcceptedResponse(ok: true, reaction: event))
        case let .failure(validationError):
            return makeJSONResponse(
                status: 400,
                payload: FailureResponse(ok: false, error: validationError.localizedDescription)
            )
        }
    }

    private func makeJSONResponse<T: Encodable>(status: Int, payload: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        let header = [
            "HTTP/1.1 \(status) \(HTTPStatus.reasonPhrase(for: status))",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var responseData = Data(header.utf8)
        responseData.append(body)
        return responseData
    }

    private func writeResponse(_ response: Data, to clientSocket: Int32) throws {
        var bytesSent = 0
        while bytesSent < response.count {
            let remainingBytes = response.count - bytesSent
            let result = response.withUnsafeBytes { buffer in
                Darwin.send(clientSocket, buffer.baseAddress!.advanced(by: bytesSent), remainingBytes, 0)
            }

            if result > 0 {
                bytesSent += result
            } else if result < 0, errno == EINTR {
                continue
            } else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
                )
            }
        }
    }

    private func resolvedPort(for socketDescriptor: Int32) -> UInt16 {
        var address = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(socketDescriptor, reboundPointer, &addressLength)
            }
        }

        guard result == 0 else {
            return requestedPort
        }

        return UInt16(bigEndian: address.sin_port)
    }
}

private struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard
            let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rawBody = Data(data[headerRange.upperBound...])
        let body: Data
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decodedBody = decodeChunkedBody(from: rawBody) else {
                return nil
            }
            body = decodedBody
        } else {
            body = rawBody
        }

        return HTTPRequest(
            method: requestParts[0].uppercased(),
            path: requestParts[1],
            headers: headers,
            body: body
        )
    }

    static func isComplete(_ data: Data) -> Bool {
        guard
            let headerRange = data.range(of: Data("\r\n\r\n".utf8)),
            let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return false
        }

        let headerLines = headerText.components(separatedBy: "\r\n").dropFirst()
        let headers = Dictionary(uniqueKeysWithValues: headerLines.compactMap { line -> (String, String)? in
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    return nil
                }

                return (
                    parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                )
            })

        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            return data[headerRange.upperBound...].range(of: Data("\r\n0\r\n\r\n".utf8)) != nil ||
                data.suffix(5) == Data("0\r\n\r\n".utf8)
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0

        return data.count - headerRange.upperBound >= contentLength
    }

    private static func decodeChunkedBody(from data: Data) -> Data? {
        var decoded = Data()
        var cursor = data.startIndex

        while cursor < data.endIndex {
            guard let lineRange = data[cursor...].range(of: Data("\r\n".utf8)) else {
                return nil
            }

            guard
                let sizeLine = String(data: data[cursor ..< lineRange.lowerBound], encoding: .utf8),
                let chunkSize = Int(sizeLine.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16)
            else {
                return nil
            }

            cursor = lineRange.upperBound
            if chunkSize == 0 {
                return decoded
            }

            let chunkEnd = cursor + chunkSize
            guard chunkEnd <= data.endIndex else {
                return nil
            }

            decoded.append(data[cursor ..< chunkEnd])
            cursor = chunkEnd

            guard
                cursor + 2 <= data.endIndex,
                data[cursor ..< cursor + 2] == Data("\r\n".utf8)
            else {
                return nil
            }

            cursor += 2
        }

        return nil
    }
}

private enum HTTPStatus {
    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 202:
            return "Accepted"
        case 404:
            return "Not Found"
        default:
            return "Bad Request"
        }
    }
}

private struct BasicResponse: Encodable {
    var ok: Bool
}

private struct FailureResponse: Encodable {
    var ok: Bool
    var error: String?
}

private struct AcceptedResponse: Encodable {
    var ok: Bool
    var reaction: PetEvent
}
