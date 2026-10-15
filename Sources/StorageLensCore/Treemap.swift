import CoreGraphics

/// Squarified treemap layout (Bruls, Huizing, van Wijk 2000).
public enum Treemap {
    /// Returns one rectangle per value, in the same order.
    /// Pass values sorted largest first for the best aspect ratios.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let n = values.count
        var out = [CGRect](repeating: .zero, count: n)
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard n > 0, total > 0, rect.width > 0, rect.height > 0 else { return out }

        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max($0, 0) * scale }
        var free = rect
        var i = 0
        while i < n {
            let side = Double(min(free.width, free.height))
            var end = i + 1
            var rowSum = areas[i]
            var current = worst(areas[i..<end], sum: rowSum, side: side)
            while end < n {
                let s = rowSum + areas[end]
                let w = worst(areas[i...end], sum: s, side: side)
                if w > current { break }
                current = w
                rowSum = s
                end += 1
            }
            free = layout(areas, i..<end, sum: rowSum, in: free, into: &out)
            i = end
        }
        return out
    }

    static func worst(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard sum > 0, side > 0, let mx = row.max(), let mn = row.min(), mn > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * mx / s2, s2 / (w2 * mn))
    }

    static func layout(_ areas: [Double], _ range: Range<Int>, sum: Double,
                       in free: CGRect, into out: inout [CGRect]) -> CGRect {
        if free.width >= free.height {
            // A column on the left side.
            let colW = free.height > 0 ? CGFloat(sum) / free.height : 0
            var y = free.minY
            for k in range {
                let h = colW > 0 ? CGFloat(areas[k]) / colW : 0
                out[k] = CGRect(x: free.minX, y: y, width: colW, height: h)
                y += h
            }
            return CGRect(x: free.minX + colW, y: free.minY, width: max(free.width - colW, 0), height: free.height)
        } else {
            // A row on the top side.
            let rowH = free.width > 0 ? CGFloat(sum) / free.width : 0
            var x = free.minX
            for k in range {
                let w = rowH > 0 ? CGFloat(areas[k]) / rowH : 0
                out[k] = CGRect(x: x, y: free.minY, width: w, height: rowH)
                x += w
            }
            return CGRect(x: free.minX, y: free.minY + rowH, width: free.width, height: max(free.height - rowH, 0))
        }
    }
}
