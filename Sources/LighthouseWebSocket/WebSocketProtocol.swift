import Foundation

public protocol WebSocketProtocol {
    /// Creates a web socket with the given URL.
    init(url: URL) async throws

    /// Connects to the server.
    func connect() async throws

    /// Registers a handler for binary messages.
    func onBinary(_ handler: @escaping (Data) -> Void) throws

    /// Sends a given binary message.
    func send(_ data: Data) async throws
}
