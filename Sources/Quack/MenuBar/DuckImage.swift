import AppKit

/// Renders the duck silhouette to a template `NSImage` using AppKit directly.
/// (`ImageRenderer` doesn't reliably rasterize a SwiftUI `Canvas`, which left
/// the menu-bar item blank.)
enum DuckImage {
    // viewBox 238 × 231 from the source SVG.
    private static let viewBox = CGSize(width: 238, height: 231)

    static func template(height: CGFloat = 17) -> NSImage {
        let scale = height / viewBox.height
        let w = viewBox.width * scale, h = viewBox.height * scale

        // SVG is Y-down; AppKit drawing is Y-up — flip Y into the image.
        let path = bezierPath(from: duckPathData) { p in
            CGPoint(x: p.x * scale, y: h - p.y * scale)
        }

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        NSColor.black.setFill()
        path.fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static let numberRegex = try! NSRegularExpression(
        pattern: #"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?"#
    )

    private static func numbers(_ s: String) -> [CGFloat] {
        let ns = s as NSString
        return numberRegex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .compactMap { Double(ns.substring(with: $0.range)).map { CGFloat($0) } }
    }

    /// Parses M/L/C/Z (absolute) — all the duck path uses — into an NSBezierPath,
    /// transforming each point through `t`.
    private static func bezierPath(from d: String, _ t: (CGPoint) -> CGPoint) -> NSBezierPath {
        let path = NSBezierPath()
        var command: Character = " "
        var segment = ""

        func flush() {
            guard command != " " else { return }
            let n = numbers(segment)
            switch command {
            case "M":
                var i = 0
                while i + 1 < n.count {
                    let p = t(CGPoint(x: n[i], y: n[i + 1]))
                    if i == 0 { path.move(to: p) } else { path.line(to: p) }
                    i += 2
                }
            case "L":
                var i = 0
                while i + 1 < n.count { path.line(to: t(CGPoint(x: n[i], y: n[i + 1]))); i += 2 }
            case "C":
                var i = 0
                while i + 5 < n.count {
                    path.curve(to: t(CGPoint(x: n[i + 4], y: n[i + 5])),
                               controlPoint1: t(CGPoint(x: n[i], y: n[i + 1])),
                               controlPoint2: t(CGPoint(x: n[i + 2], y: n[i + 3])))
                    i += 6
                }
            case "Z", "z":
                path.close()
            default:
                break
            }
            segment = ""
        }

        for ch in d {
            if ch.isLetter { flush(); command = ch } else { segment.append(ch) }
        }
        flush()
        return path
    }
}

private let duckPathData = """
M79.649 4.14277C104.792 3.41938 124.89 14.637 130.322 39.7024C130.765 41.7485 131.635 44.0781 131.917 46.1102C132.695 51.7131 133.251 60.2777 131.958 65.7691C129.023 78.2409 126.047 90.7067 123.355 103.225C128.219 99.9389 134.406 98.8781 140.169 98.3424C156.114 96.8598 170.959 100.802 186.009 105.615C193.617 108.047 201.687 111.372 209.849 110.916C212.509 110.767 216.037 110.281 218.251 108.691C220.37 107.169 221.31 104.323 224.112 103.7C225.667 103.354 227.221 103.947 228.503 104.81C231.151 106.593 233.366 118.053 234.018 121.438C237.152 137.705 233.61 156.488 226.491 171.271C224.373 175.666 221.495 180.272 218.741 184.299C210.764 195.959 195.094 211.624 181.906 217.113C172.766 220.918 163.006 222.509 153.355 224.324C149.274 224.812 144.668 225.884 140.694 226.251C127.236 227.501 112.798 227.849 99.3562 226.211C96.3918 225.85 93.4589 224.991 90.5143 224.546C84.0024 223.562 78.8646 222.026 72.7553 219.596C63.0188 215.723 54.1603 210.218 47.8125 201.678C46.2174 199.532 44.9663 198.082 43.7283 195.679C35.4556 179.749 33.1264 161.394 37.1579 143.903C37.9023 140.734 39.1085 137.831 40.0307 134.76C42.9708 124.968 48.2032 116.439 53.643 107.877C54.4432 106.574 57.9785 103.241 58.094 101.984C58.3343 98.7575 49.3927 92.9563 46.877 92.7212C35.2144 91.5886 23.2444 92.4151 11.7811 89.4593C2.28629 87.011 -0.531152 78.6122 8.47406 72.9358C10.7413 71.5067 13.0019 71.0999 15.3296 69.9537C17.9489 68.6641 20.6064 67.152 23.2304 65.8359C25.9532 64.1747 27.7559 62.3023 30.6795 60.7618C30.7014 58.0193 30.4882 55.1763 30.5207 52.4047C30.7939 29.1398 47.1294 11.2921 69.1053 5.58974C72.5027 4.7082 76.0996 4.48329 79.649 4.14277Z
"""
