// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Talks to the CasaPlay ↔ NihonSub bridge that runs on your Mac (see /companion).
// CasaPlay sends the link of the stream being played. The Mac pulls the audio, NihonSub
// transcribes and translates it, and the finished SRT comes back as subtitles.
//
// The address and token are the ones the bridge prints when it starts. Nothing is sent
// anywhere else: the bridge is on your own network.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NihonSubError: Error, Equatable, LocalizedError {
    case unreachable(String)
    case wrongToken
    case nihonSubNotRunning
    case needsGroqKey
    case ffmpegMissing
    case failed(String)
    case lostJob
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unreachable(let address):
            return "Can't reach the NihonSub bridge at \(address). Is it running on your Mac, on the same Wi-Fi?"
        case .wrongToken:
            return "The bridge refused the token. Copy the token it prints when it starts."
        case .nihonSubNotRunning:
            return "The bridge is running but NihonSub isn't. Start it again with start.sh."
        case .needsGroqKey:
            return "NihonSub has no Groq key yet. Add GROQ_API_KEY to its .env file."
        case .ffmpegMissing:
            return "FFmpeg isn't installed on the Mac. Run: brew install ffmpeg"
        case .failed(let reason):
            return reason
        case .lostJob:
            return "The bridge no longer knows this job. It may have restarted. Try again."
        case .invalidResponse:
            return "The bridge sent something unexpected."
        }
    }
}

public struct NihonSubClient: Sendable {
    public enum Language: String, CaseIterable, Sendable {
        case english = "en"
        case hindi = "hi"
        case hinglish = "hinglish"

        public var displayName: String {
            switch self {
            case .english: return "English"
            case .hindi: return "Hindi"
            case .hinglish: return "Hinglish"
            }
        }

        /// The language code stored on the subtitle track.
        public var trackLanguageCode: String { self == .english ? "en" : "hi" }
    }

    public struct Status: Equatable, Sendable {
        public var state: String
        public var percent: Int
        public var message: String
        public var error: String?

        public var isDone: Bool { state == "done" }
        public var isFailed: Bool { state == "failed" }
    }

    public var baseURL: URL
    public var token: String
    public var transport: HTTPTransport

    /// `address` is what the bridge prints, such as "192.168.1.20:3100" or "my-mac.local:3100".
    /// A missing "http://" is added. Returns nil if the address or token is empty or not usable.
    public init?(address: String, token: String, transport: HTTPTransport = URLSessionTransport()) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !trimmedToken.isEmpty else { return nil }
        let lowered = text.lowercased()
        let isWebAddress = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        // Some other kind of link (ftp://, file://) is not a bridge address.
        if !isWebAddress && lowered.contains("://") { return nil }
        if !isWebAddress { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        self.baseURL = url
        self.token = trimmedToken
        self.transport = transport
    }

    // MARK: Check

    /// Succeeds when the bridge answers, the token is right, and NihonSub and FFmpeg are ready.
    public func verify() async throws {
        let data = try await call("health")
        struct Health: Decodable { let ffmpeg: Bool?; let nihonsub: Bool?; let configured: Bool? }
        guard let health = try? JSONDecoder().decode(Health.self, from: data) else { throw NihonSubError.invalidResponse }
        if health.ffmpeg != true { throw NihonSubError.ffmpegMissing }
        if health.nihonsub != true { throw NihonSubError.nihonSubNotRunning }
        if health.configured != true { throw NihonSubError.needsGroqKey }
    }

    // MARK: Jobs

    /// Starts a job for a stream link and returns its id.
    public func start(url: URL, headers: [String: String]?, language: Language) async throws -> String {
        var body: [String: Any] = ["url": url.absoluteString, "language": language.rawValue]
        if let headers, !headers.isEmpty { body["headers"] = headers }
        let data = try await call("jobs", method: "POST", body: try JSONSerialization.data(withJSONObject: body))
        struct Created: Decodable { let id: String? }
        guard let id = (try? JSONDecoder().decode(Created.self, from: data))?.id, !id.isEmpty else {
            throw NihonSubError.invalidResponse
        }
        return id
    }

    public func status(of id: String) async throws -> Status {
        let data = try await call("jobs/\(id)")
        struct Payload: Decodable { let state: String?; let percent: Int?; let message: String?; let error: String? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), let state = payload.state else {
            throw NihonSubError.invalidResponse
        }
        return Status(state: state, percent: min(max(payload.percent ?? 0, 0), 100),
                      message: payload.message ?? "", error: payload.error)
    }

    public func srt(of id: String) async throws -> Data {
        try await call("jobs/\(id)/srt")
    }

    /// Stops a job. Best effort.
    public func cancel(_ id: String) async {
        _ = try? await call("jobs/\(id)", method: "DELETE")
    }

    /// Runs a whole job: starts it, follows its progress, and returns the finished subtitles.
    /// If the surrounding task is cancelled, the job is stopped on the Mac too.
    public func generate(
        url: URL,
        headers: [String: String]?,
        language: Language,
        pollEvery interval: TimeInterval = 2,
        onProgress: @MainActor @Sendable (Status) -> Void = { _ in }
    ) async throws -> [SubtitleCue] {
        let id = try await start(url: url, headers: headers, language: language)
        do {
            while true {
                let current = try await status(of: id)
                await onProgress(current)
                if current.isFailed {
                    throw NihonSubError.failed(current.error ?? "NihonSub couldn't make subtitles for this video.")
                }
                if current.isDone { break }
                try await Task.sleep(nanoseconds: UInt64(max(interval, 0.01) * 1_000_000_000))
            }
            let cues = SubtitleLoader.cues(from: try await srt(of: id), format: .srt)
            guard !cues.isEmpty else { throw NihonSubError.invalidResponse }
            return cues
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                let client = self
                Task.detached { await client.cancel(id) }   // a cancelled task can't send the request itself
            }
            throw error
        }
    }

    // MARK: HTTP

    private func call(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            var shown = baseURL.host ?? baseURL.absoluteString
            if let port = baseURL.port { shown += ":\(port)" }
            throw NihonSubError.unreachable(shown)
        }
        switch response.status {
        case 200..<300: return response.body
        case 401: throw NihonSubError.wrongToken
        case 404 where path.hasPrefix("jobs/"): throw NihonSubError.lostJob
        default:
            struct Failure: Decodable { let error: String? }
            if let message = (try? JSONDecoder().decode(Failure.self, from: response.body))?.error {
                throw NihonSubError.failed(message)
            }
            throw OnlineServiceError.badStatus(response.status)
        }
    }
}
