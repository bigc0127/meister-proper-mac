import Foundation
import SwiftUI

enum ANSI {
    /// Strip ANSI escape sequences (CSI ... m and others).
    static func strip(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\u{1B}" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == "[" {
                    var j = s.index(after: next)
                    while j < s.endIndex {
                        let ch = s[j]
                        if (0x40...0x7E).contains(ch.asciiValue ?? 0) { j = s.index(after: j); break }
                        j = s.index(after: j)
                    }
                    i = j
                    continue
                } else {
                    i = next < s.endIndex ? s.index(after: next) : s.endIndex
                    continue
                }
            }
            result.append(c)
            i = s.index(after: i)
        }
        return result
    }

    /// Convert ANSI-colored line to AttributedString. Supports SGR fg colors and bold.
    static func attributed(_ line: String) -> AttributedString {
        var out = AttributedString("")
        var current = AttributedString("")
        var fg: Color? = nil
        var bold = false
        var i = line.startIndex

        func flush() {
            if !current.characters.isEmpty {
                var seg = current
                if let fg { seg.foregroundColor = fg }
                if bold { seg.font = .system(.body, design: .monospaced).bold() }
                else { seg.font = .system(.body, design: .monospaced) }
                out.append(seg)
                current = AttributedString("")
            }
        }

        while i < line.endIndex {
            let c = line[i]
            if c == "\u{1B}" {
                let next = line.index(after: i)
                if next < line.endIndex, line[next] == "[" {
                    var j = line.index(after: next)
                    var codeStr = ""
                    while j < line.endIndex {
                        let ch = line[j]
                        if (0x40...0x7E).contains(ch.asciiValue ?? 0) {
                            // terminator
                            if ch == "m" { applySGR(codeStr, fg: &fg, bold: &bold, flush: flush) }
                            j = line.index(after: j); break
                        }
                        codeStr.append(ch)
                        j = line.index(after: j)
                    }
                    i = j; continue
                } else {
                    i = next < line.endIndex ? line.index(after: next) : line.endIndex
                    continue
                }
            }
            current.append(AttributedString(String(c)))
            i = line.index(after: i)
        }
        flush()
        return out
    }

    private static func applySGR(_ codes: String, fg: inout Color?, bold: inout Bool, flush: () -> Void) {
        flush()
        let parts = codes.split(separator: ";").map { Int($0) ?? 0 }
        let nums = parts.isEmpty ? [0] : parts
        for n in nums {
            switch n {
            case 0:  fg = nil; bold = false
            case 1:  bold = true
            case 22: bold = false
            case 30: fg = .black
            case 31: fg = .red
            case 32: fg = .green
            case 33: fg = .yellow
            case 34: fg = .blue
            case 35: fg = .purple
            case 36: fg = .cyan
            case 37: fg = .white
            case 90: fg = .gray
            case 91: fg = Color(red: 1, green: 0.4, blue: 0.4)
            case 92: fg = Color(red: 0.4, green: 1, blue: 0.4)
            case 93: fg = Color(red: 1, green: 0.95, blue: 0.4)
            case 94: fg = Color(red: 0.5, green: 0.7, blue: 1)
            case 95: fg = Color(red: 1, green: 0.5, blue: 1)
            case 96: fg = .cyan
            case 97: fg = .white
            case 39: fg = nil
            default: break
            }
        }
    }
}
