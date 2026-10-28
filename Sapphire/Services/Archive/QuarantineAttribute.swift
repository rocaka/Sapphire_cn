import Foundation
import Darwin

/// Propagates the downloaded archive's quarantine marker to extracted files.
/// Never follows an extracted symlink outside the destination.
enum QuarantineAttribute {
    nonisolated static func copy(from sources: [URL], to destination: URL, recursively: Bool) throws {
        let attribute = "com.apple.quarantine"
        var marker: Data?
        for source in sources {
            let count = getxattr(source.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
            if count < 0 {
                guard errno == ENOATTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                continue
            }
            var data = Data(count: count)
            let read = data.withUnsafeMutableBytes { getxattr(source.path, attribute, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
            guard read >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            data.count = read
            marker = data
            break
        }
        guard let marker else { return }
        func apply(to url: URL) throws {
            let status = marker.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, marker.count, 0, XATTR_NOFOLLOW) }
            guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        try apply(to: destination)
        if recursively, let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let url as URL in enumerator {
                if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                try apply(to: url)
            }
        }
    }
}
