import Foundation

enum TemporaryWorkspaceError: Error, Equatable {
    case invalidFileName
}

struct TemporaryWorkspace: Equatable, Sendable {
    let id: UUID
    let url: URL

    static func create(
        in rootDirectory: URL,
        id: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> TemporaryWorkspace {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )

        let workspaceURL = rootDirectory.appendingPathComponent(
            id.uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: workspaceURL.path
        )

        return TemporaryWorkspace(id: id, url: workspaceURL)
    }

    static func cleanupAbandoned(
        in rootDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }

        let children = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for child in children where UUID(uuidString: child.lastPathComponent) != nil {
            try? fileManager.removeItem(at: child)
        }
    }

    func fileURL(named fileName: String) throws -> URL {
        guard !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              URL(fileURLWithPath: fileName).lastPathComponent == fileName,
              !fileName.contains("/"),
              !fileName.contains("\\") else {
            throw TemporaryWorkspaceError.invalidFileName
        }

        return url.appendingPathComponent(fileName, isDirectory: false)
    }

    func cleanup(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
