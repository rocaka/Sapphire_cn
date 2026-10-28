import Foundation
import Darwin

@main
struct QuarantineProbe {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = root.appendingPathComponent("download.zip")
        let output = root.appendingPathComponent("extracted", isDirectory: true)
        let child = output.appendingPathComponent("file.txt")
        let outside = root.appendingPathComponent("outside.txt")
        try Data().write(to: source)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("content".utf8).write(to: child)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: output.appendingPathComponent("link"), withDestinationURL: outside)
        let marker = Data("0081;00000000;Sapphire-CN-Test;".utf8)
        let status = marker.withUnsafeBytes { setxattr(source.path, "com.apple.quarantine", $0.baseAddress, marker.count, 0, XATTR_NOFOLLOW) }
        precondition(status == 0)
        try QuarantineAttribute.copy(from: [source], to: output, recursively: true)
        precondition(getxattr(child.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == marker.count)
        precondition(getxattr(outside.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1)
        print("Archive quarantine inheritance and symlink boundary passed")
    }
}
