import SwiftUI

/// Minimal SVG path-data parser (supports M/L/H/V/C/Z, absolute and relative).
/// Enough to turn a single-path icon export into a SwiftUI `Path`.
enum SVGPath {
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"#
    )

    static func path(from d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        // Split into (command, numbers) tokens.
        var command: Character = " "
        var numbers: [CGFloat] = []
        var segment = ""

        func flush() {
            guard command != " " else { numbers = []; return }
            numbers = parseNumbers(segment)
            apply(command, numbers, into: &path, current: &current, start: &subpathStart)
            numbers = []
            segment = ""
        }

        for ch in d {
            if ch.isLetter {
                flush()
                command = ch
            } else {
                segment.append(ch)
            }
        }
        flush()
        return path
    }

    private static func parseNumbers(_ s: String) -> [CGFloat] {
        let ns = s as NSString
        return numberRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .compactMap { Double(ns.substring(with: $0.range)).map { CGFloat($0) } }
    }

    private static func apply(_ cmd: Character, _ n: [CGFloat], into path: inout Path,
                              current: inout CGPoint, start: inout CGPoint) {
        let rel = cmd.isLowercase
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        switch cmd.uppercased().first! {
        case "M":
            var i = 0
            while i + 1 < n.count {
                let p = pt(n[i], n[i + 1])
                if i == 0 { path.move(to: p); start = p } else { path.addLine(to: p) }
                current = p; i += 2
            }
        case "L":
            var i = 0
            while i + 1 < n.count { let p = pt(n[i], n[i + 1]); path.addLine(to: p); current = p; i += 2 }
        case "H":
            for x in n { let p = rel ? CGPoint(x: current.x + x, y: current.y) : CGPoint(x: x, y: current.y); path.addLine(to: p); current = p }
        case "V":
            for y in n { let p = rel ? CGPoint(x: current.x, y: current.y + y) : CGPoint(x: current.x, y: y); path.addLine(to: p); current = p }
        case "C":
            var i = 0
            while i + 5 < n.count {
                let c1 = pt(n[i], n[i + 1]), c2 = pt(n[i + 2], n[i + 3]), end = pt(n[i + 4], n[i + 5])
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; i += 6
            }
        case "Z":
            path.closeSubpath(); current = start
        default:
            break
        }
    }
}
