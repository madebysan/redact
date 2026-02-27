import Foundation

/// The .rdt project file structure (version 1).
struct ProjectFile: Codable {
    let version: Int
    let videoFile: String
    let videoPath: String?
    let language: String
    let duration: Double
    let segments: [Segment]
}

/// Serialize project state to JSON string for saving as .rdt file.
func serializeProject(segments: [Segment], language: String, duration: Double, videoFilePath: String) -> String {
    let videoFile = URL(fileURLWithPath: videoFilePath).lastPathComponent

    let project = ProjectFile(
        version: 1,
        videoFile: videoFile,
        videoPath: videoFilePath.isEmpty ? nil : videoFilePath,
        language: language,
        duration: duration,
        segments: segments
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? encoder.encode(project),
          let json = String(data: data, encoding: .utf8) else {
        return "{}"
    }

    return json
}

/// Deserialize a .rdt JSON string back into a ProjectFile.
func deserializeProject(_ json: String) throws -> ProjectFile {
    guard let data = json.data(using: .utf8) else {
        throw ProjectFileError.invalidData
    }

    let project = try JSONDecoder().decode(ProjectFile.self, from: data)

    if project.version != 1 {
        throw ProjectFileError.unsupportedVersion(project.version)
    }

    return project
}

enum ProjectFileError: LocalizedError {
    case invalidData
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid project file data"
        case .unsupportedVersion(let version):
            return "Unsupported project file version: \(version)"
        }
    }
}
