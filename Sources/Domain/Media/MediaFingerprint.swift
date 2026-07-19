import CryptoKit
import Foundation

struct MediaFingerprint: Codable, Equatable, Hashable, Sendable {
    let fileSize: Int64
    let modificationTime: Int64
    let contentDigest: String

    static func make(
        for url: URL,
        fileManager: FileManager = .default
    ) throws -> MediaFingerprint {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
        let modificationTime = Int64(
            modificationDate.timeIntervalSince1970 * 1_000_000_000
        )

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let sampleSize: UInt64 = 64 * 1024
        let unsignedSize = UInt64(max(0, fileSize))
        let offsets = Set([
            UInt64(0),
            unsignedSize > sampleSize ? unsignedSize / 2 : 0,
            unsignedSize > sampleSize ? unsignedSize - sampleSize : 0,
        ]).sorted()

        var hasher = SHA256()
        for offset in offsets {
            try handle.seek(toOffset: offset)
            if let data = try handle.read(upToCount: Int(sampleSize)) {
                hasher.update(data: data)
            }
        }

        return MediaFingerprint(
            fileSize: fileSize,
            modificationTime: modificationTime,
            contentDigest: hasher.finalize().hexString
        )
    }
}

extension SHA256.Digest {
    fileprivate var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
