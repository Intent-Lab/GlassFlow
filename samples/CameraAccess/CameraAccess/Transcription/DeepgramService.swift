import Foundation

enum DeepgramConnectionState {
  case disconnected
  case connecting
  case connected
  case error(String)
}

struct DeepgramTranscript {
  let id: String
  let text: String
  let isFinal: Bool
  let timestamp: Date
  let speaker: Int?
}

class DeepgramService: NSObject {
  var onTranscript: ((DeepgramTranscript) -> Void)?
  var onConnectionStateChanged: ((DeepgramConnectionState) -> Void)?

  private(set) var connectionState: DeepgramConnectionState = .disconnected

  private var webSocket: URLSessionWebSocketTask?
  private var urlSession: URLSession?
  private var partialCounter = 0
  private var reconnectAttempts = 0
  private let maxReconnectAttempts = 3
  private var isDisconnecting = false

  private let apiKey: String
  private let sampleRate: Int
  private let channels: Int

  init(apiKey: String, sampleRate: Int = 16000, channels: Int = 1) {
    self.apiKey = apiKey
    self.sampleRate = sampleRate
    self.channels = channels
    super.init()
  }

  func connect() {
    switch connectionState {
    case .connecting, .connected:
      return
    case .disconnected, .error:
      startConnection()
    }
  }

  private func startConnection() {
    isDisconnecting = false
    updateState(.connecting)

    var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
    components.queryItems = [
      URLQueryItem(name: "model", value: "nova-3"),
      URLQueryItem(name: "smart_format", value: "true"),
      URLQueryItem(name: "interim_results", value: "true"),
      URLQueryItem(name: "punctuate", value: "true"),
      URLQueryItem(name: "diarize", value: "true"),
      URLQueryItem(name: "encoding", value: "linear16"),
      URLQueryItem(name: "sample_rate", value: String(sampleRate)),
      URLQueryItem(name: "channels", value: String(channels)),
    ]

    guard let url = components.url else {
      updateState(.error("Invalid Deepgram URL"))
      return
    }

    var request = URLRequest(url: url)
    request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

    let config = URLSessionConfiguration.default
    urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    webSocket = urlSession?.webSocketTask(with: request)
    webSocket?.resume()

    receiveMessage()
  }

  func sendAudio(data: Data) {
    guard case .connected = connectionState else { return }
    let message = URLSessionWebSocketTask.Message.data(data)
    webSocket?.send(message) { error in
      if let error {
        NSLog("[Deepgram] Send error: %@", error.localizedDescription)
      }
    }
  }

  func disconnect() {
    isDisconnecting = true
    let closeMessage = "{\"type\": \"CloseStream\"}"
    webSocket?.send(.string(closeMessage)) { [weak self] _ in
      self?.webSocket?.cancel(with: .normalClosure, reason: nil)
    }
    cleanup()
  }

  private func cleanup() {
    webSocket = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil
    partialCounter = 0
    reconnectAttempts = 0
    updateState(.disconnected)
  }

  private func attemptReconnect() {
    guard !isDisconnecting, reconnectAttempts < maxReconnectAttempts else {
      NSLog("[Deepgram] Not reconnecting (disconnecting=%@, attempts=%d)",
            isDisconnecting ? "true" : "false", reconnectAttempts)
      return
    }
    reconnectAttempts += 1
    let delay = Double(reconnectAttempts) * 1.0
    NSLog("[Deepgram] Reconnecting in %.0fs (attempt %d/%d)", delay, reconnectAttempts, maxReconnectAttempts)

    webSocket = nil
    urlSession?.invalidateAndCancel()
    urlSession = nil

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, !self.isDisconnecting else { return }
      self.startConnection()
    }
  }

  private func updateState(_ state: DeepgramConnectionState) {
    connectionState = state
    onConnectionStateChanged?(state)
  }

  // MARK: - WebSocket Receive Loop

  private func receiveMessage() {
    webSocket?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        switch message {
        case .string(let text):
          self.handleTextMessage(text)
        case .data(let data):
          if let text = String(data: data, encoding: .utf8) {
            self.handleTextMessage(text)
          }
        @unknown default:
          break
        }
        self.receiveMessage()
      case .failure(let error):
        NSLog("[Deepgram] WebSocket receive error: %@", error.localizedDescription)
        self.updateState(.error(error.localizedDescription))
        self.attemptReconnect()
      }
    }
  }

  private func handleTextMessage(_ text: String) {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }

    let type = json["type"] as? String ?? ""

    if type == "Results" {
      guard let channel = json["channel"] as? [String: Any],
            let alternatives = channel["alternatives"] as? [[String: Any]],
            let firstAlt = alternatives.first,
            let transcript = firstAlt["transcript"] as? String,
            !transcript.isEmpty
      else { return }

      let isFinal = json["is_final"] as? Bool ?? false
      let speechFinal = json["speech_final"] as? Bool ?? false

      // Extract speaker from words if diarization is enabled
      var speaker: Int?
      if let words = firstAlt["words"] as? [[String: Any]],
         let firstWord = words.first {
        speaker = firstWord["speaker"] as? Int
      }

      if !isFinal {
        partialCounter += 1
      }

      let id = isFinal ? "final-\(Date().timeIntervalSince1970)" : "partial-\(partialCounter)"

      let result = DeepgramTranscript(
        id: id,
        text: transcript,
        isFinal: isFinal || speechFinal,
        timestamp: Date(),
        speaker: speaker
      )

      onTranscript?(result)
    } else if type == "Metadata" {
      NSLog("[Deepgram] Session started, request_id: %@", json["request_id"] as? String ?? "unknown")
    } else if type == "Error" {
      let message = json["message"] as? String ?? "Unknown error"
      NSLog("[Deepgram] API error: %@", message)
      updateState(.error(message))
      // Deepgram server errors (e.g. "internal error") -- disconnect and reconnect
      webSocket?.cancel(with: .normalClosure, reason: nil)
      webSocket = nil
      urlSession?.invalidateAndCancel()
      urlSession = nil
      attemptReconnect()
    }
  }
}

// MARK: - URLSessionWebSocketDelegate

extension DeepgramService: URLSessionWebSocketDelegate {
  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    NSLog("[Deepgram] WebSocket connected")
    reconnectAttempts = 0
    updateState(.connected)
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    NSLog("[Deepgram] WebSocket closed: %d", closeCode.rawValue)
    if !isDisconnecting && closeCode != .normalClosure {
      updateState(.error("Connection closed unexpectedly"))
      attemptReconnect()
    } else {
      cleanup()
    }
  }
}
