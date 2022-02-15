import Foundation
import MessagePack
import NIO
import WebSocketKit

/// A connection to the lighthouse server.
public class Connection {
    private let authentication: Authentication
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    private var messageListeners: [(Protocol.ServerMessage) -> Void] = []
    private var dataListeners: [(Data) -> Void] = []

    private var requestId: Int = 0
    private var webSocket: WebSocket?

    public init(authentication: Authentication) {
        self.authentication = authentication
        setUpListeners()
    }

    deinit {
        try! webSocket?.close().wait()
        try! eventLoopGroup.syncShutdownGracefully()
    }

    /// Connects to the lighthouse.
    public func connect() async throws {
        let webSocket = try await withCheckedThrowingContinuation { continuation in
            WebSocket.connect(to: "wss://lighthouse.uni-kiel.de/websocket", on: eventLoopGroup) { ws in
                continuation.resume(returning: ws)
            }.whenFailure { error in
                continuation.resume(throwing: error)
            }
        }

        webSocket.onBinary { [unowned self] (_, buf) in
            var buf = buf
            guard let data = buf.readData(length: buf.readableBytes) else {
                // TODO: Logging
                print("Could not read data")
                return
            }

            for listener in dataListeners {
                listener(data)
            }
        } 
        
        self.webSocket = webSocket
    }

    /// Sends the given display to the lighthouse.
    public func send(display: Display) async throws {
        try await send(verb: "PUT", path: ["user", authentication.username, "model"], payload: .display(display))
    }

    /// Sends the given request to the lighthouse.
    public func send(verb: String, path: [String], payload: Protocol.Payload) async throws {
        try await send(message: Protocol.ClientMessage(
            requestId: nextRequestId(),
            verb: verb,
            path: path,
            authentication: authentication,
            payload: payload
        ))
    }

    /// Sends a message to the lighthouse.
    public func send<Message>(message: Message) async throws where Message: Encodable {
        await send(data: try MessagePackEncoder().encode(message))
    }

    /// Sends binary data to the lighthouse.
    public func send(data: Data) async {
        guard let webSocket = webSocket else { fatalError("Please call .connect() before sending data!") }
        webSocket.send(Array(data))
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
                let message = try MessagePackDecoder().decode(Protocol.ServerMessage.self, from: data)

                for listener in messageListeners {
                    listener(message)
                }
            } catch {
                // TODO: Logging
                print("Error while decoding message: \(error)")
            }
        }
    }

    /// Adds a listener for generic messages.
    public func onMessage(action: @escaping (Protocol.ServerMessage) -> Void) {
        messageListeners.append(action)
    }

    /// Adds a listener for binary data.
    private func onData(action: @escaping (Data) -> Void) {
        dataListeners.append(action)
    }
}
