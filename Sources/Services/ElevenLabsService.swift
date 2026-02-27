import Foundation

/// ElevenLabs Speech-to-Speech voice conversion and history management.
class ElevenLabsService {
    private let baseURL = "https://api.elevenlabs.io/v1"

    /// Convert audio using the Speech-to-Speech API.
    /// Returns the path to the converted audio file and the history item ID (for deletion).
    func convertVoice(
        audioPath: String,
        voiceId: String,
        apiKey: String,
        outputFormat: String = "mp3_44100_128",
        onProgress: ((String) -> Void)? = nil
    ) async throws -> (audioPath: String, historyItemId: String?) {
        guard !apiKey.isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        guard !voiceId.isEmpty else {
            throw ElevenLabsError.voiceIdMissing
        }

        onProgress?("Preparing audio for voice conversion...")

        let audioURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: audioURL)

        // Build multipart/form-data request
        let boundary = UUID().uuidString
        let url = URL(string: "\(baseURL)/speech-to-speech/\(voiceId)?output_format=\(outputFormat)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Audio file part
        let filename = audioURL.lastPathComponent
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // Model ID part
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        body.append("eleven_english_sts_v2")
        body.append("\r\n")

        // Close boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        onProgress?("Sending audio to ElevenLabs...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        // Save converted audio to temp directory
        let outputPath = PathUtilities.tempDir + "/converted_audio.mp3"
        try? FileManager.default.removeItem(atPath: outputPath)
        try data.write(to: URL(fileURLWithPath: outputPath))

        // Extract history item ID from response headers
        let historyItemId = httpResponse.value(forHTTPHeaderField: "history-item-id")

        onProgress?("Voice conversion complete")

        return (audioPath: outputPath, historyItemId: historyItemId)
    }

    /// Fetch voices available on the user's account.
    func listVoices(apiKey: String) async throws -> [(id: String, name: String, category: String)] {
        guard !apiKey.isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }

        let url = URL(string: "\(baseURL)/voices")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voices = json["voices"] as? [[String: Any]] else {
            throw ElevenLabsError.invalidResponse
        }

        return voices.compactMap { voice in
            guard let id = voice["voice_id"] as? String,
                  let name = voice["name"] as? String else { return nil }
            let category = voice["category"] as? String ?? ""
            return (id: id, name: name, category: category)
        }
    }

    /// Delete a history item from ElevenLabs servers (for privacy).
    func deleteHistoryItem(historyItemId: String, apiKey: String) async throws {
        guard !apiKey.isEmpty else { return }

        let url = URL(string: "\(baseURL)/history/\(historyItemId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Non-critical — don't throw, just log
            return
        }
    }
}

// MARK: - Errors

enum ElevenLabsError: LocalizedError {
    case apiKeyMissing
    case voiceIdMissing
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ElevenLabs API key is not configured. Set it in Preferences."
        case .voiceIdMissing:
            return "No voice ID specified for voice recreation."
        case .requestFailed(let code, let message):
            return "ElevenLabs API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from ElevenLabs API."
        }
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
