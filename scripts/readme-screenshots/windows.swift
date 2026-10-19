// Prints "<window id>\t<width>x<height>\t<title>" for one process's on-screen windows.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: windows <pid>\n".data(using: .utf8)!)
    exit(2)
}
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
    guard let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
    let width = Int(bounds["Width"] as? Double ?? 0), height = Int(bounds["Height"] as? Double ?? 0)
    print("\(number)\t\(width)x\(height)\t\(window[kCGWindowName as String] as? String ?? "")")
}
