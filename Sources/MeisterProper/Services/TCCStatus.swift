import Foundation

/// Probes whether the app has Full Disk Access by attempting to enumerate
/// known TCC-locked directories. If readdir succeeds → has FDA.
enum TCCStatus {
    static func hasFullDiskAccess() -> Bool {
        let h = NSHomeDirectory()
        // Cookies dir is FDA-locked; readdir returns "Operation not permitted" without FDA.
        let probes = [
            "\(h)/Library/Cookies",
            "\(h)/Library/Safari",
        ]
        for p in probes {
            if (try? FileManager.default.contentsOfDirectory(atPath: p)) != nil {
                return true
            }
        }
        return false
    }
}
