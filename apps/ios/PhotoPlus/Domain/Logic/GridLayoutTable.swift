import CoreGraphics

/// Where grid cells sit, computed rather than measured. Reading positions from every cell while scrolling
/// costs too much on a phone, and the grid's layout is simple enough to work out.
struct GridLayoutTable {
    let columns: Int
    let width: CGFloat
    let spacing: CGFloat
    let count: Int
    /// The top of each cell in a single-column grid, whose rows differ in height.
    private let tops: [CGFloat]
    private let heights: [CGFloat]

    var cellWidth: CGFloat {
        (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private var rowPitch: CGFloat { cellWidth + spacing }

    init(aspectRatios: [CGFloat], columns: Int, width: CGFloat, spacing: CGFloat = 1.7) {
        self.columns = max(columns, 1)
        self.width = width
        self.spacing = spacing
        count = aspectRatios.count
        guard self.columns == 1 else {
            tops = []
            heights = []
            return
        }
        var tops: [CGFloat] = []
        var heights: [CGFloat] = []
        tops.reserveCapacity(count)
        heights.reserveCapacity(count)
        var top: CGFloat = 0
        for ratio in aspectRatios {
            let height = width / max(ratio, 0.01)
            tops.append(top)
            heights.append(height)
            top += height + spacing
        }
        self.tops = tops
        self.heights = heights
    }

    func frame(at index: Int) -> CGRect {
        if columns == 1 {
            return CGRect(x: 0, y: tops[index], width: width, height: heights[index])
        }
        let row = index / columns
        let column = index % columns
        return CGRect(x: CGFloat(column) * rowPitch, y: CGFloat(row) * rowPitch, width: cellWidth, height: cellWidth)
    }

    /// The first item of the row at a height in the grid, or nil for an empty grid.
    func index(atY y: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        if columns == 1 {
            var low = 0
            var high = count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if tops[middle] <= y { low = middle } else { high = middle - 1 }
            }
            return low
        }
        let row = max(Int(y / rowPitch), 0)
        return min(row * columns, (count - 1) / columns * columns)
    }
}
