import AppKit

/// Which pixels of a render differ from its background (the top-left pixel), in points from the
/// top-left corner. For hosted layout tests that read where things landed.
struct InkMap {
    private let inked: [Bool]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init(_ rep: NSBitmapImageRep, size: CGSize) {
        width = rep.pixelsWide
        height = rep.pixelsHigh
        scale = CGFloat(rep.pixelsWide) / size.width
        let data = rep.bitmapData!
        let bytesPerPixel = rep.bitsPerPixel / 8
        let background = (0..<bytesPerPixel).map { data[$0] }
        var inked = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rep.bytesPerRow + x * bytesPerPixel
                inked[y * width + x] = (0..<bytesPerPixel).contains { abs(Int(data[offset + $0]) - Int(background[$0])) > 24 }
            }
        }
        self.inked = inked
    }

    /// `host` as drawn now.
    @MainActor
    init(of host: NSView) {
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        self.init(rep, size: host.bounds.size)
    }

    func count(x: Range<CGFloat>, y: Range<CGFloat>) -> Int {
        var count = 0
        for row in pixels(y, limit: height) {
            for column in pixels(x, limit: width) where inked[row * width + column] { count += 1 }
        }
        return count
    }

    /// The box around the inked pixels of the rows in `y`, or nil when there are none.
    func bounds(y: Range<CGFloat>) -> CGRect? {
        var minX = width, maxX = -1, minY = height, maxY = -1
        for row in pixels(y, limit: height) {
            for column in 0..<width where inked[row * width + column] {
                minX = min(minX, column); maxX = max(maxX, column)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= minX else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }

    private func pixels(_ points: Range<CGFloat>, limit: Int) -> Range<Int> {
        max(0, Int(points.lowerBound * scale))..<min(limit, Int(points.upperBound * scale))
    }
}
