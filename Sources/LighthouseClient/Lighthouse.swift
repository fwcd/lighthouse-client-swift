import Foundation
import Logging
import MessagePack
import NIO
import WebSocketKit
import LighthouseProtocol

private let log = Logger(label: "LighthouseClient.Lighthouse")

/// A connection to the lighthouse server.
public class Lighthouse {
    /// The WbeSocket URL of the connected lighthouse server.
    private let url: URL
    /// The user's authentication credentials.
    private let authentication: Authentication
    /// The event loop group on which the WebSocket connection runs.
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    private var inputListeners: [(InputEvent) -> Void] = []
    private var frameListeners: [(Frame) -> Void] = []
    private var messageListeners: [(ServerMessage) -> Void] = []
    private var dataListeners: [(Data) -> Void] = []

    /// The next request id.
    private var requestId: Int = 0
    /// The WebSocket connection.
    private var webSocket: WebSocket?

    public init(
        authentication: Authentication,
        url: URL = lighthouseUrl
    ) {
        self.authentication = authentication
        self.url = url
        setUpListeners()
    }

    deinit {
        _ = webSocket?.close()
        eventLoopGroup.shutdownGracefully { error in
            guard let error = error else { return }
            log.error("Error while shutting down event loop group: \(error)")
        }
    }

    /// Connects to the lighthouse.
    public func connect() async throws {
        let webSocket = try await withCheckedThrowingContinuation { continuation in
            WebSocket.connect(to: url, on: eventLoopGroup) { ws in
                continuation.resume(returning: ws)
            }.whenFailure { error in
                continuation.resume(throwing: error)
            }
        }

        webSocket.onBinary { [unowned self] (_, buf) in
            var buf = buf
            guard let data = buf.readData(length: buf.readableBytes) else {
                log.warning("Could not read data from WebSocket")
                return
            }

            for listener in dataListeners {
                listener(data)
            }
        } 
        
        self.webSocket = webSocket
    }

    /// Sends the given frame to the lighthouse.
    public func send(frame: Frame) async throws {
        try await send(verb: "PUT", path: ["user", authentication.username, "model"], payload: .frame(frame))
    }

    /// Requests a stream of events (such as input) from the lighthouse.
    public func requestStream() async throws {
        try await send(verb: "STREAM", path: ["user", authentication.username, "model"])
    }

    /// Sends the given request to the lighthouse.
    public func send(verb: String, path: [String], payload: Payload = .other) async throws {
        try await send(message: ClientMessage(
            requestId: nextRequestId(),
            verb: verb,
            path: path,
            authentication: authentication,
            payload: payload
        ))
    }

    /// Sends a message to the lighthouse.
    public func send<Message>(message: Message) async throws where Message: Encodable {
        let data = try MessagePackEncoder().encode(message)
        try await send(data: data)
    }

    /// Sends binary data to the lighthouse.
    public func send(data: Data) async throws {
        guard let webSocket = webSocket else { fatalError("Please call .connect() before sending data!") }
        let promise = eventLoopGroup.next().makePromise(of: Void.self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            promise.futureResult.whenComplete {
                continuation.resume(with: $0)
            }
            webSocket.send(Array(data), promise: promise)
        }
    }

    /// Fetches the next request id for sending.
    private func nextRequestId() -> Int {
        let id = requestId
        requestId += 1
        return id
    }

    /// Sets up the listeners for received messages.
    private func setUpListeners() {
        onData { [unowned self] data in
            do {
                let message = try MessagePackDecoder().decode(ServerMessage.self, from: data)

                for listener in messageListeners {
                    listener(message)
                }
            } catch {
                log.warning("Error while decoding message: \(error)")
            }
        }

        onMessage { [unowned self] message in
            switch message.payload {
            case .inputEvent(let inputEvent):
                for listener in inputListeners {
                    listener(inputEvent)
                }
            case .frame(let frame):
                for listener in frameListeners {
                    listener(frame)
                }
            default:
                break
            }
        }
    }

    /// Adds a listener for key/controller input.
    /// Will only fire if .requestStream() was called.
    public func onInput(action: @escaping (InputEvent) -> Void) {
        inputListeners.append(action)
    }

    /// Adds a listener for frames.
    /// Will only fire if .requestStream() was called.
    public func onFrame(action: @escaping (Frame) -> Void) {
        frameListeners.append(action)
    }

    /// Adds a listener for generic messages.
    public func onMessage(action: @escaping (ServerMessage) -> Void) {
        messageListeners.append(action)
    }

    /// Adds a listener for binary data.
    private func onData(action: @escaping (Data) -> Void) {
        dataListeners.append(action)
    }
}
