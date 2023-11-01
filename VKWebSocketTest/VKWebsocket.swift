import Foundation

public protocol WebsocketDelegate: AnyObject {
  func websocket(_ websocket: VKWebsocket, didReceive message: URLSessionWebSocketTask.Message)
  func websocket(_ websocket: VKWebsocket, didError error: Error?)
  func websocket(_ websocket: VKWebsocket, didChange connectionState: VKWebsocket.ConnectionState)
}

public actor VKWebsocket {
 public enum ConnectionState {
    case connected
    case connecting
    case disconnected
  }

  private(set) weak var delegate: WebsocketDelegate?

  private(set) var reconnectOnFailure = true
  private(set) var connectionState = ConnectionState.disconnected {
    didSet {
      guard oldValue != connectionState else { return }
      let newState = connectionState
      self.delegate?.websocket(self, didChange: newState)
    }
  }

  private let request: URLRequest
  private var session: URLSession?
  private var task: URLSessionWebSocketTask?
  private var messagesQueue: [URLSessionWebSocketTask.Message] = []
  private lazy var urlSessionDelegate = WebsocketURLSessionDelegate(websocket: self)

  public init(request: URLRequest) {
    self.request = request
  }

  deinit {
    print("deinit \(type(of: self))")
    task?.cancel()
    session?.finishTasksAndInvalidate()
  }

  public func setDelegate(_ delegate: WebsocketDelegate) {
    self.delegate = delegate
  }

  public func connect() {
    guard connectionState == .disconnected else { return }
    connectionState = .connecting
    session = URLSession(configuration: .ephemeral,
                         delegate: urlSessionDelegate,
                         delegateQueue: nil)
    task = session?.webSocketTask(with: request)
    task?.resume()
  }

  public func disconnect() {
    task?.cancel(with: .normalClosure, reason: nil)
    session?.finishTasksAndInvalidate()
    session = nil
    task = nil
    connectionState = .disconnected
  }

  public func sendMessage(message: URLSessionWebSocketTask.Message) {
    guard connectionState == .connected else {
      messagesQueue.append(message)
      return
    }

    // VKWebsocket does not re-enqueue messages that fail. Clients implementing VKWebsocket
    // should handle resending failed messages.
    task?.send(message, completionHandler: { [weak self] error in
      guard let self = self else { return }
      Task {
        await self.delegate?.websocket(self, didError: error)
      }
    })
  }

  private func awaitMessage() {
    guard connectionState == .connected else { return }
    task?.receive(completionHandler: { [weak self] result in
      guard let self = self else { return }
      Task {
        await self.onReceive(result: result)
      }
    })
  }

  private func onReceive(result: Result<URLSessionWebSocketTask.Message, Error>) {
    switch result {
    case .success(let message):
      self.delegate?.websocket(self, didReceive: message)
      self.awaitMessage()
    case .failure(let error):
      self.delegate?.websocket(self, didError: error)
      self.handleFailure()
    }
  }

  private func handleFailure() {
    disconnect()
  }

  fileprivate func websocketConnectionDidOpen() {
    connectionState = .connected

    awaitMessage()

    messagesQueue.forEach { message in
      self.sendMessage(message: message)
    }

    messagesQueue = []
  }

  fileprivate func websocketConnectionDidClose() {
    connectionState = .disconnected
  }

  fileprivate func websocketConnectionDidError(_ error: Error?) {
    delegate?.websocket(self, didError: error)
    handleFailure()
  }
}

// URLSession strongly retains its delegate, for whatever reason. We use an intermediate
// class to break the resulting retain cycle.
private class WebsocketURLSessionDelegate: NSObject, URLSessionWebSocketDelegate {
  weak var websocket: VKWebsocket?

  init(websocket: VKWebsocket) {
    self.websocket = websocket
  }

  deinit {
    print("deinit \(type(of: self))")
  }

  func urlSession(_ session: URLSession,
                  webSocketTask: URLSessionWebSocketTask,
                  didOpenWithProtocol protocol: String?) {
    Task {
      await self.websocket?.websocketConnectionDidOpen()
    }
  }

  func urlSession(_ session: URLSession,
                  webSocketTask: URLSessionWebSocketTask,
                  didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                  reason: Data?) {
    Task {
      await self.websocket?.websocketConnectionDidClose()
    }
  }

  func urlSession(_ session: URLSession,
                  task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    // This method will be called when you deinit VKWebsocket while connection is open.
    Task {
      await self.websocket?.websocketConnectionDidError(error)
    }
  }
}
