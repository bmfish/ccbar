import Cocoa
import SQLite3

// MARK: - Design System (借鉴 CCSwitcher 风格)

enum Design {
    // 品牌色
    static let brandColor = NSColor(red: 0xE8/255, green: 0x6D/255, blue: 0x45/255, alpha: 1.0) // #E86D45
    static let accentColor = NSColor.systemBlue

    // 卡片样式
    static let cardCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardShadowRadius: CGFloat = 5
    static let cardShadowOffset: CGFloat = 6

    // 进度条
    static let barCornerRadius: CGFloat = 3
    static let barHeight: CGFloat = 7

    // 间距
    static let sectionSpacing: CGFloat = 16
    static let itemSpacing: CGFloat = 8

    // 颜色（深色模式）
    static let backgroundDark = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
    static let cardFillDark = NSColor.black.withAlphaComponent(0.21)
    static let cardBorderDark = NSColor.white.withAlphaComponent(0.20)
    static let textPrimary = NSColor.white
    static let textSecondary = NSColor.white.withAlphaComponent(0.55)
    static let textMuted = NSColor(white: 0.6, alpha: 1.0)

    // 好的状态色
    static let successColor = NSColor.systemGreen
    static let warningColor = NSColor.systemOrange
    static let errorColor = NSColor.systemRed

    // MARK: - 用量色阶（浅绿 → 黄 → 橙 → 红）

    /// 用量色阶的关键色（按进度 0.0 ~ 1.0 排列）
    private static let usageStops: [(pos: CGFloat, color: NSColor)] = [
        (0.00, NSColor(red: 0.42, green: 0.85, blue: 0.62, alpha: 1.0)),  // 浅绿
        (0.35, NSColor(red: 0.65, green: 0.87, blue: 0.45, alpha: 1.0)),  // 黄绿
        (0.60, NSColor(red: 0.95, green: 0.80, blue: 0.35, alpha: 1.0)),  // 黄
        (0.82, NSColor(red: 0.95, green: 0.58, blue: 0.28, alpha: 1.0)),  // 橙
        (1.00, NSColor(red: 0.90, green: 0.28, blue: 0.30, alpha: 1.0)),  // 红
    ]

    /// 按用量占总量的比例取色（progress: 0.0 浅绿 → 1.0 红）
    static func usageColor(progress: CGFloat) -> NSColor {
        let p = min(max(progress, 0), 1)

        // 找到所在区间
        for i in 0..<(usageStops.count - 1) {
            let a = usageStops[i]
            let b = usageStops[i + 1]
            if p <= b.pos {
                let span = b.pos - a.pos
                let t = span > 0 ? (p - a.pos) / span : 0
                guard let c1 = a.color.usingColorSpace(.sRGB),
                      let c2 = b.color.usingColorSpace(.sRGB) else { return a.color }
                return NSColor(
                    red:   c1.redComponent   + (c2.redComponent   - c1.redComponent)   * t,
                    green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * t,
                    blue:  c1.blueComponent  + (c2.blueComponent  - c1.blueComponent)  * t,
                    alpha: 1.0
                )
            }
        }
        return usageStops.last!.color
    }

    /// 根据今日用量和预警阈值计算颜色
    ///
    /// 色阶锚点（以预警阈值为参照）：
    /// - 0.25× 阈值 → 浅绿
    /// - 0.75× 阈值 → 黄
    /// - 1.00× 阈值 → 橙红（刚好达到预警线）
    /// - ≥1.2× 阈值 → 正红
    ///
    /// - Parameters:
    ///   - total: 今日 token 总量
    ///   - thresholdWan: 预警阈值（万为单位，来自设置）
    static func usageColor(total: Int64, thresholdWan: Int) -> NSColor {
        let threshold = Double(thresholdWan) * 10_000
        guard threshold > 0 else { return usageStops.first!.color }

        // 阈值对应 0.83 进度（橙红），1.2× 阈值对应满格红色
        let rawProgress = Double(total) / threshold
        let progress = rawProgress / 1.2
        return usageColor(progress: CGFloat(min(progress, 1.0)))
    }

    // MARK: - 模型配色（按小时轮换）

    /// 模型配色的基础色带
    private static let baseModelColors: [NSColor] = [
        brandColor,                                                  // 品牌橙
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0),     // 蓝
        NSColor(red: 0.30, green: 0.76, blue: 0.54, alpha: 1.0),     // 绿
        NSColor(red: 0.95, green: 0.65, blue: 0.35, alpha: 1.0),     // 橙
        NSColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1.0),     // 紫
        NSColor(red: 0.96, green: 0.45, blue: 0.71, alpha: 1.0),     // 粉
    ]

    /// 极简确定性随机数（LCG），用于按种子洗牌
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
    }

    /// 当前小时的种子（同一小时内保持稳定）
    private static func hourSeed() -> UInt64 {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date())
        return UInt64((c.year ?? 0) * 1_000_000 + (c.month ?? 0) * 10_000
                      + (c.day ?? 0) * 100 + (c.hour ?? 0))
    }

    /// 模型配色：每小时换一次顺序
    ///
    /// 同一小时内主页与详情页颜色一致；跨小时自动换一套。
    static func modelColors(count: Int = 6) -> [NSColor] {
        var colors = baseModelColors
        var rng = SeededRandom(seed: hourSeed())

        // Fisher-Yates 洗牌
        if colors.count > 1 {
            for i in stride(from: colors.count - 1, through: 1, by: -1) {
                let j = Int(rng.next() % UInt64(i + 1))
                colors.swapAt(i, j)
            }
        }

        // 需要更多颜色时循环补足
        var result: [NSColor] = []
        for i in 0..<count {
            result.append(colors[i % colors.count])
        }
        return result
    }

    // 格式化数字
    static func formatTokens(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.2f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else {
            return "\(n)"
        }
    }

    static func formatTokensK(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.2f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else {
            return "\(n)"
        }
    }
}

// MARK: - 自定义视图组件

/// Sparkline 小图表（支持渐变色折线）
class SparklineView: NSView {
    var values: [CGFloat] = []
    var lineColor: NSColor = Design.brandColor
    var fillColor: NSColor = Design.brandColor.withAlphaComponent(0.15)

    /// 渐变模式：折线按位置取渐变色
    var useGradient: Bool = false
    /// 色相偏移（0.0 ~ 1.0），让不同时间段的图表呈现不同色系
    var hueOffset: CGFloat = 0
    /// 渐变色带
    var gradientColors: [NSColor] = [
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0),  // 蓝
        NSColor(red: 0.40, green: 0.78, blue: 0.75, alpha: 1.0),  // 青
        NSColor(red: 0.45, green: 0.82, blue: 0.50, alpha: 1.0),  // 绿
        NSColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1.0),  // 黄
        Design.brandColor,                                         // 橙
        NSColor(red: 0.90, green: 0.45, blue: 0.60, alpha: 1.0)   // 粉
    ]

    /// 在渐变色带上按进度取色，并按 hueOffset 旋转色相
    private func gradientColor(at progress: CGFloat) -> NSColor {
        guard gradientColors.count >= 2 else { return lineColor }
        let p = min(max(progress, 0), 1)
        let scaled = p * CGFloat(gradientColors.count - 1)
        let idx = min(Int(scaled), gradientColors.count - 2)
        let t = scaled - CGFloat(idx)

        guard let c1 = gradientColors[idx].usingColorSpace(.sRGB),
              let c2 = gradientColors[idx + 1].usingColorSpace(.sRGB) else {
            return gradientColors[idx]
        }

        let r = c1.redComponent   + (c2.redComponent   - c1.redComponent)   * t
        let g = c1.greenComponent + (c2.greenComponent - c1.greenComponent) * t
        let b = c1.blueComponent  + (c2.blueComponent  - c1.blueComponent)  * t

        guard hueOffset != 0 else {
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        let base = NSColor(red: r, green: g, blue: b, alpha: 1.0).usingColorSpace(.sRGB) ?? NSColor.white
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        return NSColor(hue: (h + hueOffset).truncatingRemainder(dividingBy: 1.0),
                       saturation: s, brightness: br, alpha: 1.0)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard values.count > 1 else { return }

        let maxVal = values.max() ?? 1
        let minVal = values.min() ?? 0
        let range = maxVal - minVal

        let stepX = bounds.width / CGFloat(values.count - 1)
        let padding: CGFloat = 4
        let availableHeight = bounds.height - padding * 2
        let count = values.count

        // 计算点
        var points: [NSPoint] = []
        for (i, val) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let normalized = range > 0 ? (val - minVal) / range : 0.5
            let y = padding + normalized * availableHeight
            points.append(NSPoint(x: x, y: y))
        }

        // 填充区域（垂直渐变，从线的颜色淡出到底部）
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: points[0].x, y: padding))
        for point in points {
            fillPath.line(to: point)
        }
        fillPath.line(to: NSPoint(x: points.last!.x, y: padding))
        fillPath.close()

        let topColor: NSColor
        if useGradient {
            topColor = gradientColor(at: 0.5).withAlphaComponent(0.22)
        } else {
            topColor = fillColor
        }
        let bottomColor = topColor.withAlphaComponent(0.0)

        if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
            gradient.draw(in: fillPath, angle: 90)
        } else {
            topColor.setFill()
            fillPath.fill()
        }

        // 绘制折线：逐段取渐变色，圆角连接保证平滑
        for i in 0..<(count - 1) {
            let segment = NSBezierPath()
            segment.lineWidth = 2
            segment.lineCapStyle = .round
            segment.lineJoinStyle = .round
            segment.move(to: points[i])
            segment.line(to: points[i + 1])

            let color: NSColor
            if useGradient {
                let progress = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0.5
                color = gradientColor(at: progress)
            } else {
                color = lineColor
            }
            color.setStroke()
            segment.stroke()
        }

        // 绘制终点圆点（用最后一个点的颜色）
        if let lastPoint = points.last {
            let dotRadius: CGFloat = 3.5
            let dotRect = NSRect(x: lastPoint.x - dotRadius, y: lastPoint.y - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            let endColor = useGradient ? gradientColor(at: 1.0) : lineColor
            endColor.setFill()
            dotPath.fill()

            // 外圈描边增强可见性
            let ringPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2))
            ringPath.lineWidth = 1.5
            endColor.withAlphaComponent(0.35).setStroke()
            ringPath.stroke()
        }
    }
}

/// 进度条视图
class ProgressBarView: NSView {
    var progress: CGFloat = 0 // 0.0 ~ 1.0
    var trackColor: NSColor = NSColor.white.withAlphaComponent(0.15)
    var fillColor: NSColor = Design.brandColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 轨道
        let trackRect = NSRect(x: 0, y: (bounds.height - Design.barHeight) / 2,
                              width: bounds.width, height: Design.barHeight)
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: Design.barCornerRadius,
                                    yRadius: Design.barCornerRadius)
        trackColor.setFill()
        trackPath.fill()

        // 填充
        let fillWidth = bounds.width * min(max(progress, 0), 1)
        if fillWidth > 0 {
            let fillRect = NSRect(x: 0, y: (bounds.height - Design.barHeight) / 2,
                                 width: fillWidth, height: Design.barHeight)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: Design.barCornerRadius,
                                       yRadius: Design.barCornerRadius)
            fillColor.setFill()
            fillPath.fill()
        }
    }
}

/// 柱状图视图
class BarChartView: NSView {
    var values: [CGFloat] = []
    var labels: [String] = []
    var barColor: NSColor = Design.brandColor
    var highlightColor: NSColor = Design.accentColor
    var highlightIndex: Int = -1  // 高亮某一天（如今天）

    /// 渐变模式：每根柱子按位置取渐变色，不再是单一颜色
    var useGradient: Bool = false
    /// 色相偏移（0.0 ~ 1.0），让不同日期的图表呈现不同的色系
    var hueOffset: CGFloat = 0
    /// 渐变色带（从第一个颜色平滑过渡到最后一个）
    var gradientColors: [NSColor] = [
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0),  // 蓝
        NSColor(red: 0.40, green: 0.78, blue: 0.75, alpha: 1.0),  // 青
        NSColor(red: 0.45, green: 0.82, blue: 0.50, alpha: 1.0),  // 绿
        NSColor(red: 0.95, green: 0.78, blue: 0.35, alpha: 1.0),  // 黄
        Design.brandColor,                                         // 橙
        NSColor(red: 0.90, green: 0.45, blue: 0.60, alpha: 1.0)   // 粉
    ]

    /// 在渐变色带上按进度取色（0.0 ~ 1.0），并按 hueOffset 旋转色相
    private func gradientColor(at progress: CGFloat) -> NSColor {
        guard gradientColors.count >= 2 else { return barColor }
        let p = min(max(progress, 0), 1)
        let scaled = p * CGFloat(gradientColors.count - 1)
        let idx = min(Int(scaled), gradientColors.count - 2)
        let t = scaled - CGFloat(idx)

        guard let c1 = gradientColors[idx].usingColorSpace(.sRGB),
              let c2 = gradientColors[idx + 1].usingColorSpace(.sRGB) else {
            return gradientColors[idx]
        }

        let r = c1.redComponent   + (c2.redComponent   - c1.redComponent)   * t
        let g = c1.greenComponent + (c2.greenComponent - c1.greenComponent) * t
        let b = c1.blueComponent  + (c2.blueComponent  - c1.blueComponent)  * t

        guard hueOffset != 0 else {
            return NSColor(red: r, green: g, blue: b, alpha: 1.0)
        }

        // 转 HSB 做色相旋转，再转回 RGB
        let base = NSColor(red: r, green: g, blue: b, alpha: 1.0).usingColorSpace(.sRGB) ?? NSColor.white
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        return NSColor(hue: (h + hueOffset).truncatingRemainder(dividingBy: 1.0),
                       saturation: s, brightness: br, alpha: 1.0)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !values.isEmpty else { return }

        let maxVal = values.max() ?? 1
        let padding: CGFloat = 4
        let labelHeight: CGFloat = 16
        let availableHeight = bounds.height - labelHeight - padding * 2
        let barWidth = max(8, (bounds.width - padding * 2) / CGFloat(values.count) - 4)
        let count = values.count

        for (i, val) in values.enumerated() {
            let x = padding + CGFloat(i) * (barWidth + 4)
            let barHeight = max(2, (val / maxVal) * availableHeight)
            let y = padding + (availableHeight - barHeight)

            // 柱子
            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: 3, yRadius: 3)

            let color: NSColor
            if i == highlightIndex {
                color = highlightColor
            } else if useGradient {
                // 按柱子位置在色带上取色（只有一根柱子时用中间色）
                let progress = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0.5
                color = gradientColor(at: progress)
            } else {
                color = barColor
            }
            color.setFill()
            barPath.fill()

            // 标签
            if i < labels.count && i % 2 == 0 {  // 隔一个显示标签
                let label = NSTextField(labelWithString: labels[i])
                label.font = NSFont.systemFont(ofSize: 8)
                label.textColor = Design.textMuted
                label.alignment = .center
                label.frame = NSRect(x: x - 2, y: 0, width: barWidth + 4, height: labelHeight)
                addSubview(label)
            }
        }
    }
}

/// 环形图视图（用于模型分布）
class DonutChartView: NSView {
    struct Segment {
        let value: CGFloat
        let color: NSColor
        let label: String
    }

    var segments: [Segment] = []
    var lineWidth: CGFloat = 20

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !segments.isEmpty else { return }

        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0 else { return }

        let center = NSPoint(x: bounds.width / 2, y: bounds.height / 2)
        let radius = min(bounds.width, bounds.height) / 2 - lineWidth / 2
        var startAngle: CGFloat = 90  // 从顶部开始

        for segment in segments {
            let angle = (segment.value / total) * 360
            let endAngle = startAngle - angle

            // 绘制弧线
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            segment.color.setStroke()
            path.stroke()

            startAngle = endAngle
        }

        // 中心文字
        let totalLabel = NSTextField(labelWithString: Design.formatTokens(Int64(total)))
        totalLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        totalLabel.textColor = Design.textPrimary
        totalLabel.alignment = .center
        let labelSize = totalLabel.intrinsicContentSize
        totalLabel.frame = NSRect(x: center.x - labelSize.width / 2,
                                  y: center.y - labelSize.height / 2,
                                  width: labelSize.width, height: labelSize.height)
        addSubview(totalLabel)
    }
}

/// 带标签的环形图（包含图例）
class DonutChartWithLegendView: NSView {
    struct Item {
        let value: CGFloat
        let color: NSColor
        let label: String
        let percentage: String
    }

    var items: [Item] = []
    var donutSize: CGFloat = 120

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !items.isEmpty else { return }

        // 绘制环形图
        let donutFrame = NSRect(x: 0, y: (bounds.height - donutSize) / 2, width: donutSize, height: donutSize)
        let donutView = DonutChartView(frame: donutFrame)
        donutView.segments = items.map { DonutChartView.Segment(value: $0.value, color: $0.color, label: $0.label) }
        donutView.lineWidth = 18
        addSubview(donutView)

        // 绘制图例
        var legendY: CGFloat = bounds.height - 20
        let legendX: CGFloat = donutSize + 16
        let colorSize: CGFloat = 10
        let lineHeight: CGFloat = 18

        for item in items.prefix(6) {  // 最多显示6个
            // 颜色块
            let colorRect = NSRect(x: legendX, y: legendY, width: colorSize, height: colorSize)
            let colorPath = NSBezierPath(roundedRect: colorRect, xRadius: 2, yRadius: 2)
            item.color.setFill()
            colorPath.fill()

            // 标签
            let labelField = NSTextField(labelWithString: item.label)
            labelField.font = NSFont.systemFont(ofSize: 11)
            labelField.textColor = Design.textPrimary
            labelField.frame = NSRect(x: legendX + colorSize + 6, y: legendY - 2, width: 100, height: 14)
            addSubview(labelField)

            // 百分比
            let percentField = NSTextField(labelWithString: item.percentage)
            percentField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            percentField.textColor = Design.textSecondary
            percentField.alignment = .right
            percentField.frame = NSRect(x: bounds.width - 40, y: legendY - 2, width: 35, height: 14)
            addSubview(percentField)

            legendY -= lineHeight
        }
    }
}

/// 渐变顶部条（品牌色到背景色，提升精致感）
class GradientHeaderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let startColor = Design.brandColor.withAlphaComponent(0.6)
        let endColor = Design.brandColor.withAlphaComponent(0.0)
        if let gradient = NSGradient(starting: startColor, ending: endColor) {
            gradient.draw(in: bounds, angle: 0)
        }
    }
}

/// 卡片容器视图（带阴影和圆角）
class CardContainerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        Design.cardFillDark.setFill()
        bgPath.fill()

        // 边框
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        Design.cardBorderDark.setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()

        // 阴影
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        self.shadow = shadow
    }
}

/// 卡片容器视图
class CardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                  xRadius: Design.cardCornerRadius,
                                  yRadius: Design.cardCornerRadius)
        Design.cardFillDark.setFill()
        bgPath.fill()

        // 边框
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: Design.cardCornerRadius,
                                      yRadius: Design.cardCornerRadius)
        Design.cardBorderDark.setStroke()
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
}

// MARK: - Settings

class Settings {
    let defaults = UserDefaults.standard

    var refreshInterval: Int {
        get { defaults.integer(forKey: "refreshInterval") == 0 ? 30 : defaults.integer(forKey: "refreshInterval") }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    var dbPath: String {
        get { defaults.string(forKey: "dbPath") ?? "\(NSHomeDirectory())/.cc-switch/cc-switch.db" }
        set { defaults.set(newValue, forKey: "dbPath") }
    }

    var warningThreshold: Int {
        get { defaults.integer(forKey: "warningThreshold") == 0 ? 50 : defaults.integer(forKey: "warningThreshold") }
        set { defaults.set(newValue, forKey: "warningThreshold") }
    }

    var warningEnabled: Bool {
        get { defaults.object(forKey: "warningEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "warningEnabled") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
}

// 数据缓存
class DataCache {
    static let shared = DataCache()

    private var todayStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
    private var yesterdayStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
    private var weekStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
    private var monthStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
    private var totalStats: (reqs: Int, total: Int64)?
    private var modelBreakdown: [(model: String, input: Int64, output: Int64, total: Int64)]?
    private var lastUpdate: Date = Date.distantPast
    private var lastDailyCacheDate: String?  // 记录上次缓存昨日/7天/30天数据的日期
    private var lastModelCacheDate: String?  // 记录上次缓存模型分布的小时

    func getCachedToday() -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        return todayStats
    }

    func getCachedYesterday() -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        return yesterdayStats
    }

    func getCachedWeek() -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        return weekStats
    }

    func getCachedMonth() -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        return monthStats
    }

    func getCachedTotal() -> (reqs: Int, total: Int64)? {
        return totalStats
    }

    func getCachedModelBreakdown() -> [(model: String, input: Int64, output: Int64, total: Int64)]? {
        return modelBreakdown
    }

    func needsDailyCache() -> Bool {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        return lastDailyCacheDate != today
    }

    func needsModelCache() -> Bool {
        guard let lastDate = lastModelCacheDate else { return true }
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        let currentHour = formatter.string(from: now)
        let lastHour = String(lastDate.prefix(2))
        return currentHour != lastHour
    }

    func update(
        today: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        yesterday: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        week: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        month: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        total: (reqs: Int, total: Int64)?,
        models: [(model: String, input: Int64, output: Int64, total: Int64)]?
    ) {
        self.todayStats = today
        // 只在需要时更新昨日/7天/30天/总量数据
        if yesterday != nil {
            self.yesterdayStats = yesterday
        }
        if week != nil {
            self.weekStats = week
        }
        if month != nil {
            self.monthStats = month
        }
        if total != nil {
            self.totalStats = total
        }
        if models != nil {
            self.modelBreakdown = models
        }
        self.lastUpdate = Date()
    }

    func markDailyCacheDone() {
        lastDailyCacheDate = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
    }

    func markModelCacheDone() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        lastModelCacheDate = formatter.string(from: Date())
    }

    func getLastUpdateTime() -> Date {
        return lastUpdate
    }
}

// MARK: - Popover View Controller (类似 CCSwitcher 风格)

class PopoverViewController: NSViewController {
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!

    override func loadView() {
        // 创建主视图
        let mainView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        mainView.wantsLayer = true
        mainView.layer?.backgroundColor = Design.backgroundDark.cgColor

        // 滚动视图 - 填满整个区域
        scrollView = NSScrollView(frame: mainView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalRuler = false
        scrollView.hasHorizontalScroller = false
        mainView.addSubview(scrollView)

        // 内容栈 - 紧凑布局
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 2  // 减小间距
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 2, right: 12)  // 减小底部内边距

        let clipView = NSClipView()
        clipView.documentView = contentStack
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: clipView.bottomAnchor)
        ])

        self.view = mainView
    }

    /// 刷新内容（每次显示时调用，确保数据一致）
    func refresh() {
        buildContent()
    }

    private func buildContent() {
        // 清空
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 获取数据
        let today = AppDelegate.shared?.queryDayStats(days: 0)
        let yesterday = AppDelegate.shared?.queryDayStats(days: 1)
        let week = AppDelegate.shared?.queryDayStats(days: 7)
        let month = AppDelegate.shared?.queryDayStats(days: 30)
        let total = AppDelegate.shared?.queryTotalStats()
        let models = AppDelegate.shared?.queryModelBreakdown()

        // MARK: - 渐变顶部条（品牌色 → 背景，提升精致感）
        let gradientBar = GradientHeaderView()
        gradientBar.translatesAutoresizingMaskIntoConstraints = false
        gradientBar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        contentStack.addArrangedSubview(gradientBar)
        gradientBar.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: 0).isActive = true

        // MARK: - 问候语
        let greeting = AppDelegate.shared?.greetings.randomElement() ?? "ccBar 用量统计"
        let greetingLabel = NSTextField(labelWithString: greeting)
        greetingLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        greetingLabel.textColor = Design.textSecondary
        greetingLabel.maximumNumberOfLines = 1
        greetingLabel.lineBreakMode = .byTruncatingTail
        greetingLabel.alignment = .center
        contentStack.addArrangedSubview(greetingLabel)
        greetingLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true

        // MARK: - 今日统计卡片
        if let today = today {
            // 标题行
            let headerView = createCompactHeader("📊 今日用量", action: #selector(AppDelegate.openHourlyDetailToday))
            contentStack.addArrangedSubview(headerView)
            headerView.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true

            // 大数字（带发光效果）
            let thresholdWan = AppDelegate.shared?.settings.warningThreshold ?? 50
            let usageColor = Design.usageColor(total: today.total, thresholdWan: thresholdWan)

            let bigNumber = NSTextField(labelWithString: Design.formatTokens(today.total))
            bigNumber.font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
            bigNumber.textColor = usageColor
            // 发光阴影
            let glow = NSShadow()
            glow.shadowColor = usageColor.withAlphaComponent(0.35)
            glow.shadowBlurRadius = 16
            glow.shadowOffset = .zero
            bigNumber.shadow = glow
            contentStack.addArrangedSubview(bigNumber)

            // 三列统计
            let statsRow = NSView()
            statsRow.translatesAutoresizingMaskIntoConstraints = false
            statsRow.heightAnchor.constraint(equalToConstant: 44).isActive = true  // 增加高度
            contentStack.addArrangedSubview(statsRow)
            statsRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true

            let totalInput = today.input + today.cacheCreate + today.cacheRead
            let cacheRate = totalInput > 0 ? Double(today.cacheRead) / Double(totalInput) * 100 : 0

            // 请求数列
            let reqColumn = NSView()
            reqColumn.translatesAutoresizingMaskIntoConstraints = false
            statsRow.addSubview(reqColumn)

            let reqLabel = NSTextField(labelWithString: "请求数")
            reqLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)  // 增大字号
            reqLabel.textColor = Design.textMuted
            reqLabel.translatesAutoresizingMaskIntoConstraints = false
            reqColumn.addSubview(reqLabel)

            let reqValue = NSTextField(labelWithString: "\(today.reqs)次")
            reqValue.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)  // 增大字号
            reqValue.textColor = Design.textPrimary
            reqValue.translatesAutoresizingMaskIntoConstraints = false
            reqColumn.addSubview(reqValue)

            NSLayoutConstraint.activate([
                reqColumn.leadingAnchor.constraint(equalTo: statsRow.leadingAnchor),
                reqColumn.topAnchor.constraint(equalTo: statsRow.topAnchor),
                reqColumn.bottomAnchor.constraint(equalTo: statsRow.bottomAnchor),
                reqColumn.widthAnchor.constraint(equalTo: statsRow.widthAnchor, multiplier: 0.33),
                reqLabel.topAnchor.constraint(equalTo: reqColumn.topAnchor, constant: 6),  // 增加顶部间距
                reqLabel.centerXAnchor.constraint(equalTo: reqColumn.centerXAnchor),
                reqValue.topAnchor.constraint(equalTo: reqLabel.bottomAnchor, constant: 4),  // 增加标签和数值间距
                reqValue.centerXAnchor.constraint(equalTo: reqColumn.centerXAnchor)
            ])

            // 缓存命中列
            let cacheColumn = NSView()
            cacheColumn.translatesAutoresizingMaskIntoConstraints = false
            statsRow.addSubview(cacheColumn)

            let cacheLabel = NSTextField(labelWithString: "缓存命中")
            cacheLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)  // 增大字号
            cacheLabel.textColor = Design.textMuted
            cacheLabel.translatesAutoresizingMaskIntoConstraints = false
            cacheColumn.addSubview(cacheLabel)

            let cacheValue = NSTextField(labelWithString: String(format: "%.0f%%", cacheRate))
            cacheValue.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)  // 增大字号
            cacheValue.textColor = cacheRate > 80 ? Design.successColor : Design.warningColor
            cacheValue.translatesAutoresizingMaskIntoConstraints = false
            cacheColumn.addSubview(cacheValue)

            NSLayoutConstraint.activate([
                cacheColumn.leadingAnchor.constraint(equalTo: reqColumn.trailingAnchor),
                cacheColumn.topAnchor.constraint(equalTo: statsRow.topAnchor),
                cacheColumn.bottomAnchor.constraint(equalTo: statsRow.bottomAnchor),
                cacheColumn.widthAnchor.constraint(equalTo: statsRow.widthAnchor, multiplier: 0.33),
                cacheLabel.topAnchor.constraint(equalTo: cacheColumn.topAnchor, constant: 6),  // 增加顶部间距
                cacheLabel.centerXAnchor.constraint(equalTo: cacheColumn.centerXAnchor),
                cacheValue.topAnchor.constraint(equalTo: cacheLabel.bottomAnchor, constant: 4),  // 增加标签和数值间距
                cacheValue.centerXAnchor.constraint(equalTo: cacheColumn.centerXAnchor)
            ])

            // 时长列
            if let hours = AppDelegate.shared?.queryWorkHours() {
                let hoursColumn = NSView()
                hoursColumn.translatesAutoresizingMaskIntoConstraints = false
                statsRow.addSubview(hoursColumn)

                let hoursLabel = NSTextField(labelWithString: "时长")
                hoursLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)  // 增大字号
                hoursLabel.textColor = Design.textMuted
                hoursLabel.translatesAutoresizingMaskIntoConstraints = false
                hoursColumn.addSubview(hoursLabel)

                let hoursValue = NSTextField(labelWithString: "\(hours)h")
                hoursValue.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)  // 增大字号
                hoursValue.textColor = Design.textPrimary
                hoursValue.translatesAutoresizingMaskIntoConstraints = false
                hoursColumn.addSubview(hoursValue)

                NSLayoutConstraint.activate([
                    hoursColumn.leadingAnchor.constraint(equalTo: cacheColumn.trailingAnchor),
                    hoursColumn.trailingAnchor.constraint(equalTo: statsRow.trailingAnchor),
                    hoursColumn.topAnchor.constraint(equalTo: statsRow.topAnchor),
                    hoursColumn.bottomAnchor.constraint(equalTo: statsRow.bottomAnchor),
                    hoursLabel.topAnchor.constraint(equalTo: hoursColumn.topAnchor, constant: 6),  // 增加顶部间距
                    hoursLabel.centerXAnchor.constraint(equalTo: hoursColumn.centerXAnchor),
                    hoursValue.topAnchor.constraint(equalTo: hoursLabel.bottomAnchor, constant: 4),  // 增加标签和数值间距
                    hoursValue.centerXAnchor.constraint(equalTo: hoursColumn.centerXAnchor)
                ])
            }

            addSeparator()
        }

        // MARK: - 模型分布
        if let models = models, !models.isEmpty {
            let headerView = createCompactHeader("🤖 模型分布", action: #selector(AppDelegate.openModelDetailToday))
            contentStack.addArrangedSubview(headerView)
            headerView.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true

            // 模型配色（与环形图一致，按小时轮换）
            let modelColors = Design.modelColors()

            let maxTotal = models.prefix(3).map { $0.total }.max() ?? 1
            for (index, model) in models.prefix(3).enumerated() {
                addCompactModelBar(
                    name: model.model,
                    value: model.total,
                    maxValue: maxTotal,
                    color: modelColors[index % modelColors.count]
                )
            }

            addSeparator()
        }

        // MARK: - 时间段统计
        if let yesterday = yesterday {
            addCompactStatRow(icon: "📅", title: "昨日", value: Design.formatTokens(yesterday.total),
                            action: #selector(AppDelegate.openHourlyDetailYesterday))
        }

        if let week = week {
            addCompactStatRow(icon: "📊", title: "近7天", value: Design.formatTokens(week.total),
                            action: #selector(AppDelegate.openDetail))
        }

        if let month = month {
            addCompactStatRow(icon: "📆", title: "近30天", value: Design.formatTokens(month.total),
                            action: #selector(AppDelegate.openMonthDetail))
        }

        if let total = total {
            addCompactStatRow(icon: "📊", title: "历史总量", value: Design.formatTokens(total.total),
                            action: #selector(AppDelegate.openMonthDetail))
        }

        addSeparator()

        // MARK: - 操作按钮（水平排列）
        let buttonBar = NSView()
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.heightAnchor.constraint(equalToConstant: 40).isActive = true  // 增加高度
        contentStack.addArrangedSubview(buttonBar)
        buttonBar.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true

        // 复制按钮
        let copyBtn = createHorizontalButton(icon: "📋", title: "复制", action: #selector(AppDelegate.copyStats))
        buttonBar.addSubview(copyBtn)

        // 刷新按钮
        let refreshBtn = createHorizontalButton(icon: "🔄", title: "刷新", action: #selector(AppDelegate.refreshData))
        buttonBar.addSubview(refreshBtn)

        // 设置按钮
        let settingsBtn = createHorizontalButton(icon: "⚙️", title: "设置", action: #selector(AppDelegate.openSettingsAndClose))
        buttonBar.addSubview(settingsBtn)

        // 退出按钮
        let quitBtn = createHorizontalButton(icon: "❌", title: "退出", action: #selector(AppDelegate.quit))
        buttonBar.addSubview(quitBtn)

        // 使用 NSStackView 水平排列按钮
        let buttonStack = NSStackView(views: [copyBtn, refreshBtn, settingsBtn, quitBtn])
        buttonStack.orientation = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor)
        ])
    }

    // MARK: - Helper Methods (紧凑版本)

    private func createCompactHeader(_ title: String, action: Selector) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Design.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        // 箭头指示器
        let arrow = NSTextField(labelWithString: "›")
        arrow.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        arrow.textColor = Design.textMuted
        arrow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(arrow)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            arrow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            arrow.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: AppDelegate.shared, action: action)
        container.addGestureRecognizer(clickGesture)

        return container
    }

    private func addStatColumn(to parent: NSView, x: CGFloat, label: String, value: String, color: NSColor) {
        let container = NSView(frame: NSRect(x: x, y: 0, width: 90, height: 32))

        let labelField = NSTextField(frame: NSRect(x: 0, y: 16, width: 90, height: 12))
        labelField.stringValue = label
        labelField.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        labelField.textColor = Design.textMuted
        container.addSubview(labelField)

        let valueField = NSTextField(frame: NSRect(x: 0, y: 2, width: 90, height: 14))
        valueField.stringValue = value
        valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueField.textColor = color
        container.addSubview(valueField)

        parent.addSubview(container)
    }

    private func addCompactModelBar(name: String, value: Int64, maxValue: Int64, color: NSColor) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 36).isActive = true  // 增加高度，不再拥挤

        let shortName = name.count > 16 ? String(name.prefix(16)) + "..." : name

        // 颜色圆点
        let dot = NSView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 3
        container.addSubview(dot)

        let nameLabel = NSTextField(labelWithString: shortName)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = Design.textPrimary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        let valueLabel = NSTextField(labelWithString: Design.formatTokensK(value))
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = Design.textSecondary
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(valueLabel)

        let progressBar = ProgressBarView()
        progressBar.progress = maxValue > 0 ? CGFloat(value) / CGFloat(maxValue) : 0
        progressBar.fillColor = color  // 使用模型专属颜色
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressBar)

        NSLayoutConstraint.activate([
            // 颜色圆点
            dot.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            // 模型名
            nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -8),

            // 数值
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            // 进度条
            progressBar.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 7),
            progressBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 6)
        ])

        contentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
    }

    private func addCompactStatRow(icon: String, title: String, value: String, action: Selector) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = NSFont.systemFont(ofSize: 12)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconLabel)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = Design.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = Design.textSecondary
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(valueLabel)

        let arrow = NSTextField(labelWithString: "›")
        arrow.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        arrow.textColor = Design.textMuted
        arrow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(arrow)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -4),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            arrow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            arrow.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: AppDelegate.shared, action: action)
        container.addGestureRecognizer(clickGesture)

        contentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
    }

    private func addCompactActionButton(icon: String, title: String, action: Selector) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = NSFont.systemFont(ofSize: 12)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconLabel)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = Design.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let clickGesture = NSClickGestureRecognizer(target: AppDelegate.shared, action: action)
        container.addGestureRecognizer(clickGesture)

        contentStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
    }

    private func createHorizontalButton(icon: String, title: String, action: Selector) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        container.layer?.cornerRadius = 6

        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = NSFont.systemFont(ofSize: 16)  // 增大图标
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconLabel)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 10)  // 减小字号确保显示完整
        titleLabel.textColor = Design.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 3),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -2)
        ])

        let clickGesture = NSClickGestureRecognizer(target: AppDelegate.shared, action: action)
        container.addGestureRecognizer(clickGesture)

        return container
    }

    private func addSeparator() {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        contentStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -24).isActive = true
    }

    private func calculateCacheRate(_ stats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)) -> Double {
        let totalInput = stats.input + stats.cacheCreate + stats.cacheRead
        return totalInput > 0 ? Double(stats.cacheRead) / Double(totalInput) * 100 : 0
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static var shared: AppDelegate?

    var statusItem: NSStatusItem!
    var timer: Timer?
    var db: OpaquePointer?
    let settings = Settings()
    var settingsWindow: SettingsWindowController?
    var detailWindow: DetailWindowController?
    var monthWindow: MonthDetailWindowController?
    var hourlyWindow: HourlyDetailWindowController?
    var modelWindow: ModelDetailWindowController?
    var lastNotificationDate: Date?
    var currentHourlyDate: Date?

    // MARK: - 里程碑动画
    /// 上次触发冒泡的 token 档位（每 1000万 一档）
    var lastTokenTier: Int = 0
    /// 冒泡窗口池（避免窗口被提前释放）
    var bubbleWindows: [NSWindow] = []

    // 随机问候语
    let greetings = [
        "今天也要加油写 Bug 哦 ✨",
        "代码如诗，Bug 如风 🌸",
        "写代码不如谈恋爱 💕",
        "需求又改了，习惯就好 🫠",
        "今天不出 Bug，明天出什么 🎯",
        "写代码使我快乐（并不）🎭",
        "技术债也是债 💸",
        "今天的需求明天再做 🌙",
        "码农的一天从咖啡开始 ☕",
        "Git commit -m '又一个 Bug' 🔧",
        "产品经理说很简单 🤡",
        "这个需求一天就能做完 📝",
        "代码能跑就行 🏃",
        "今天也是充满 Bug 的一天 🐛",
        "先实现，再优化（永远不优化）⏳",
        "这个接口我三分钟就写完 ⚡",
        "测试？什么测试？ 🎲",
        "线上出 Bug 了？不可能 🚫",
        "重构？先加个 if 吧 🤔",
        "这个功能很简单的 🎪"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 初始数据库连接
        connectDB()

        // 初始化历史备份表
        initHistoryTable()

        // 备份历史数据（启动时执行一次）
        backupHistory()

        // 设置点击事件（使用 popover 替代 menu）
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 初始更新
        updateData()

        // 定时器
        startTimer()
    }

    var popover: NSPopover?
    var eventMonitor: Any?

    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        if popover == nil {
            let popover = NSPopover()
            popover.contentSize = NSSize(width: 300, height: 420)
            popover.behavior = .applicationDefined
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = PopoverViewController()
            self.popover = popover
        }

        // 每次显示时刷新数据，确保与标题一致
        if let vc = popover?.contentViewController as? PopoverViewController {
            vc.refresh()
        }

        if let button = statusItem.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        // 添加全局事件监听器
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                if let popover = self?.popover, popover.isShown {
                    self?.closePopover()
                }
            }
        }
    }

    func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        removeEventMonitor()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }

    func connectDB() {
        let dbPath = settings.dbPath
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("无法打开数据库: \(dbPath)")
            db = nil
        }
    }

    func initHistoryTable() {
        guard let db = db else { return }

        let sql = """
        CREATE TABLE IF NOT EXISTS proxy_request_logs_history (
            request_id TEXT PRIMARY KEY,
            provider_id TEXT NOT NULL,
            app_type TEXT NOT NULL,
            model TEXT NOT NULL,
            request_model TEXT,
            input_tokens INTEGER NOT NULL DEFAULT 0,
            output_tokens INTEGER NOT NULL DEFAULT 0,
            cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
            input_cost_usd TEXT NOT NULL DEFAULT '0',
            output_cost_usd TEXT NOT NULL DEFAULT '0',
            cache_read_cost_usd TEXT NOT NULL DEFAULT '0',
            cache_creation_cost_usd TEXT NOT NULL DEFAULT '0',
            total_cost_usd TEXT NOT NULL DEFAULT '0',
            latency_ms INTEGER NOT NULL,
            first_token_ms INTEGER,
            duration_ms INTEGER,
            status_code INTEGER NOT NULL,
            error_message TEXT,
            session_id TEXT,
            provider_type TEXT,
            is_streaming INTEGER NOT NULL DEFAULT 0,
            cost_multiplier TEXT NOT NULL DEFAULT '1.0',
            created_at INTEGER NOT NULL,
            data_source TEXT NOT NULL DEFAULT 'proxy',
            pricing_model TEXT,
            input_token_semantics INTEGER NOT NULL DEFAULT 0,
            backed_up_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
        """

        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("创建历史备份表失败")
        } else {
            print("历史备份表已就绪")
        }
    }

    func backupHistory() {
        guard let db = db else { return }

        // 获取上次备份日期
        let lastBackupDate = UserDefaults.standard.string(forKey: "lastHistoryBackupDate") ?? "2000-01-01"

        // 计算昨天的日期
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterdayStr = formatter.string(from: yesterday)

        // 如果已经备份过昨天，跳过
        guard lastBackupDate < yesterdayStr else {
            print("历史数据已是最新（上次备份: \(lastBackupDate)）")
            return
        }

        // 备份从上次备份日期到昨天的数据
        let sql = """
        INSERT OR IGNORE INTO proxy_request_logs_history
        SELECT
            request_id, provider_id, app_type, model, request_model,
            input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
            input_cost_usd, output_cost_usd, cache_read_cost_usd, cache_creation_cost_usd,
            total_cost_usd, latency_ms, first_token_ms, duration_ms,
            status_code, error_message, session_id, provider_type,
            is_streaming, cost_multiplier, created_at, data_source,
            pricing_model, input_token_semantics,
            strftime('%s', 'now') as backed_up_at
        FROM proxy_request_logs
        WHERE date(created_at, 'unixepoch', 'localtime') > ?
          AND date(created_at, 'unixepoch', 'localtime') <= ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("准备备份语句失败")
            return
        }

        sqlite3_bind_text(stmt, 1, lastBackupDate, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, yesterdayStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        if sqlite3_step(stmt) == SQLITE_DONE {
            let changes = sqlite3_changes(db)
            print("历史备份完成: 新增 \(changes) 条记录（\(lastBackupDate) ~ \(yesterdayStr)）")

            // 更新备份日期
            UserDefaults.standard.set(yesterdayStr, forKey: "lastHistoryBackupDate")
        } else {
            print("历史备份失败")
        }

        sqlite3_finalize(stmt)
    }

    func checkAndRunScheduledBackup() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // 检查是否是备份时间（11:00 或 20:00）
        let isBackupTime = (hour == 11 && minute == 0) || (hour == 20 && minute == 0)

        guard isBackupTime else { return }

        // 获取今天是否已经备份过
        let lastBackupDate = UserDefaults.standard.string(forKey: "lastHistoryBackupDate") ?? "2000-01-01"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterdayStr = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: now)!)

        // 如果20:00检查，且已经备份到昨天，跳过
        if hour == 20 && lastBackupDate >= yesterdayStr {
            print("20:00 检查：历史数据已是最新，跳过备份")
            return
        }

        // 执行备份
        print("执行定时备份（\(hour):00）")
        backupHistory()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(settings.refreshInterval),
                                     target: self,
                                     selector: #selector(updateData),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc func updateData() {
        // 检查是否需要执行定时备份（11:00 或 20:00）
        checkAndRunScheduledBackup()

        // 查询今日统计（每次刷新都查）
        let todayStats = queryDayStats(days: 0)

        // 模型分布每小时刷新一次
        var modelBreakdown: [(model: String, input: Int64, output: Int64, total: Int64)]?
        if DataCache.shared.needsModelCache() {
            modelBreakdown = queryModelBreakdown()
            DataCache.shared.markModelCacheDone()
        }

        // 昨日/7天/30天/总量数据只在当天第一次刷新时查询
        var yesterdayStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
        var weekStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
        var monthStats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?
        var totalStats: (reqs: Int, total: Int64)?

        if DataCache.shared.needsDailyCache() {
            yesterdayStats = queryDayStats(days: 1)
            weekStats = queryDayStats(days: 7)
            monthStats = queryDayStats(days: 30)
            totalStats = queryTotalStats()
            DataCache.shared.markDailyCacheDone()
        }

        // 更新缓存
        DataCache.shared.update(
            today: todayStats,
            yesterday: yesterdayStats,
            week: weekStats,
            month: monthStats,
            total: totalStats,
            models: modelBreakdown
        )

        // 更新标题（统一用 attributedTitle，避免与 flash 动画冲突）
        if let stats = todayStats {
            let totalStr = fmtTitle(stats.total)
            let thresholdWan = settings.warningThreshold
            let color = Design.usageColor(total: stats.total, thresholdWan: thresholdWan)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            ]
            statusItem.button?.attributedTitle = NSAttributedString(string: totalStr, attributes: attrs)

            // 检查预警
            checkWarning(stats: stats)

            // 检查里程碑（每1000万冒泡 + 闪标题）
            checkTokenMilestone(stats.total)
        } else {
            statusItem.button?.title = "未找到"
        }

        // 不设置图标，只显示数字
        statusItem.button?.image = nil

        // 更新菜单
        updateMenu()
    }

    func queryDayStats(days: Int) -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        guard let db = db else { return nil }

        // 计算时间范围（本地时间）
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startTimestamp = Int64(startOfDay.timeIntervalSince1970)

        var stmt: OpaquePointer?
        let sql: String
        var bindValue: Int64?

        if days == 0 {
            // 今日
            sql = """
            SELECT
                COUNT(*) as reqs,
                COALESCE(SUM(input_tokens), 0) as input,
                COALESCE(SUM(output_tokens), 0) as output,
                COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
                COALESCE(SUM(cache_read_tokens), 0) as cache_read
            FROM proxy_request_logs
            WHERE created_at >= ?
            """
            bindValue = startTimestamp
        } else if days == 1 {
            // 昨日
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
            sql = """
            SELECT
                COUNT(*) as reqs,
                COALESCE(SUM(input_tokens), 0) as input,
                COALESCE(SUM(output_tokens), 0) as output,
                COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
                COALESCE(SUM(cache_read_tokens), 0) as cache_read
            FROM proxy_request_logs
            WHERE created_at >= ? AND created_at < ?
            """
            // 需要绑定两个值，在下面处理
            bindValue = Int64(yesterdayStart.timeIntervalSince1970)
        } else {
            // 近N天
            let startDate = calendar.date(byAdding: .day, value: -days, to: startOfDay)!
            sql = """
            SELECT
                COUNT(*) as reqs,
                COALESCE(SUM(input_tokens), 0) as input,
                COALESCE(SUM(output_tokens), 0) as output,
                COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
                COALESCE(SUM(cache_read_tokens), 0) as cache_read
            FROM proxy_request_logs
            WHERE created_at >= ?
            """
            bindValue = Int64(startDate.timeIntervalSince1970)
        }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        if let value = bindValue {
            sqlite3_bind_int64(stmt, 1, value)
        }

        // 对于昨日查询，需要绑定第二个参数
        if days == 1 {
            sqlite3_bind_int64(stmt, 2, startTimestamp)
        }

        var result: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?

        if sqlite3_step(stmt) == SQLITE_ROW {
            let reqs = Int(sqlite3_column_int(stmt, 0))
            let input = sqlite3_column_int64(stmt, 1)
            let output = sqlite3_column_int64(stmt, 2)
            let cacheCreate = sqlite3_column_int64(stmt, 3)
            let cacheRead = sqlite3_column_int64(stmt, 4)
            let total = input + output + cacheCreate + cacheRead
            result = (reqs, input, output, cacheCreate, cacheRead, total)
        }

        sqlite3_finalize(stmt)
        return result
    }

    func queryModelBreakdown() -> [(model: String, input: Int64, output: Int64, total: Int64)]? {
        guard let db = db else { return nil }

        // 计算今天的开始时间（本地时间）
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startTimestamp = Int64(startOfDay.timeIntervalSince1970)

        var stmt: OpaquePointer?
        let sql = """
        SELECT
            model,
            COALESCE(SUM(input_tokens), 0) as input,
            COALESCE(SUM(output_tokens), 0) as output,
            COALESCE(SUM(input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens), 0) as total
        FROM proxy_request_logs
        WHERE created_at >= ?
        GROUP BY model
        ORDER BY total DESC
        LIMIT 5
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_int64(stmt, 1, startTimestamp)

        var breakdown: [(model: String, input: Int64, output: Int64, total: Int64)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let input = sqlite3_column_int64(stmt, 1)
            let output = sqlite3_column_int64(stmt, 2)
            let total = sqlite3_column_int64(stmt, 3)
            breakdown.append((model, input, output, total))
        }

        sqlite3_finalize(stmt)
        return breakdown.isEmpty ? nil : breakdown
    }

    func queryWorkHours() -> String? {
        guard let db = db else { return nil }

        // 计算今天的开始时间（本地时间）
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startTimestamp = Int64(startOfDay.timeIntervalSince1970)

        var stmt: OpaquePointer?
        let sql = """
        SELECT MIN(created_at)
        FROM proxy_request_logs
        WHERE created_at >= ?
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_int64(stmt, 1, startTimestamp)

        var result: String?

        if sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(stmt, 0)
            if timestamp > 0 {
                let startDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let hours = Date().timeIntervalSince(startDate) / 3600
                if hours > 0 {
                    result = String(format: "%.1f", hours)
                }
            }
        }

        sqlite3_finalize(stmt)
        return result
    }

    func queryTotalStats() -> (reqs: Int, total: Int64)? {
        guard let db = db else { return nil }

        // 总量 = proxy_request_logs 全部 + usage_daily_rollups 中更早的部分
        // （避免与日志重叠：只取 rollup 中 date < 日志最早日期 的行）
        var stmt: OpaquePointer?
        let sql = """
        SELECT SUM(reqs), SUM(total) FROM (
            SELECT COUNT(*) as reqs,
                   COALESCE(SUM(input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens), 0) as total
            FROM proxy_request_logs
            UNION ALL
            SELECT COALESCE(SUM(request_count), 0) as reqs,
                   COALESCE(SUM(input_tokens + output_tokens + cache_creation_tokens + cache_read_tokens), 0) as total
            FROM usage_daily_rollups
            WHERE date < (SELECT date(MIN(created_at), 'unixepoch', 'localtime') FROM proxy_request_logs)
        )
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        var result: (reqs: Int, total: Int64)?

        if sqlite3_step(stmt) == SQLITE_ROW {
            let reqs = Int(sqlite3_column_int(stmt, 0))
            let total = sqlite3_column_int64(stmt, 1)
            result = (reqs: reqs, total: total)
        }

        sqlite3_finalize(stmt)
        return result
    }

    func queryDailyBreakdown(days: Int) -> [(date: String, reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, cost: Double)]? {
        guard let db = db else { return nil }

        var stmt: OpaquePointer?
        let sql = """
        SELECT
            date(created_at, 'unixepoch', 'localtime') as day,
            COUNT(*) as reqs,
            COALESCE(SUM(input_tokens), 0) as input,
            COALESCE(SUM(output_tokens), 0) as output,
            COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
            COALESCE(SUM(cache_read_tokens), 0) as cache_read,
            COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0) as cost
        FROM proxy_request_logs
        WHERE created_at >= strftime('%s', date('now', 'localtime', '-' || ? || ' days'))
        GROUP BY day
        ORDER BY day DESC
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        sqlite3_bind_int(stmt, 1, Int32(days))

        var breakdown: [(date: String, reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, cost: Double)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let date = String(cString: sqlite3_column_text(stmt, 0))
            let reqs = Int(sqlite3_column_int(stmt, 1))
            let input = sqlite3_column_int64(stmt, 2)
            let output = sqlite3_column_int64(stmt, 3)
            let cacheCreate = sqlite3_column_int64(stmt, 4)
            let cacheRead = sqlite3_column_int64(stmt, 5)
            let cost = sqlite3_column_double(stmt, 6)
            breakdown.append((date, reqs, input, output, cacheCreate, cacheRead, cost))
        }

        sqlite3_finalize(stmt)
        return breakdown.isEmpty ? nil : breakdown
    }

    func checkWarning(stats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)) {
        guard settings.warningEnabled else { return }

        // 检查今天是否已经通知过
        let todayKey = "warningNotified_\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))"
        if UserDefaults.standard.bool(forKey: todayKey) {
            return // 今天已通知过
        }

        // 检查是否超过阈值（阈值单位是万，需要乘以10000）
        let thresholdInTokens = Int64(settings.warningThreshold) * 10000
        if stats.total >= thresholdInTokens {
            // 发送通知
            sendNotification(total: stats.total, threshold: thresholdInTokens)
            // 标记今天已通知
            UserDefaults.standard.set(true, forKey: todayKey)
        }
    }

    func sendNotification(total: Int64, threshold: Int64) {
        let notification = NSUserNotification()
        notification.title = "用量预警"
        notification.informativeText = "今日 Token 用量已达 \(fmtK(total))，超过预警阈值 \(settings.warningThreshold)万"
        notification.soundName = NSUserNotificationDefaultSoundName

        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - 里程碑动画（每1000万冒泡 + 闪标题）

    /// 每1000万 token 为一档，跨档时触发动画
    func checkTokenMilestone(_ total: Int64) {
        let tier = Int(total / 10_000_000)  // 每1000万一档
        guard tier > lastTokenTier, tier > 0 else { return }
        lastTokenTier = tier

        // 计算增量（跨了几档就显示多少）
        let deltaTokens = total % 10_000_000 == 0 ? 10_000_000 : total - Int64(tier - 1) * 10_000_000

        // 触发冒泡
        showBubble(delta: deltaTokens)

        // 触发标题闪烁
        flashTitle()
    }

    /// 状态栏附近弹出 "🫧 +X万" 泡泡，上升并淡出
    func showBubble(delta: Int64) {
        guard let button = statusItem.button, let window = button.window else { return }

        // 泡泡内容
        let text = "🫧 +\(fmtK(delta))"

        // 创建临时窗口
        let bubbleW: CGFloat = 100
        let bubbleH: CGFloat = 32
        let bubble = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        bubble.isOpaque = false
        bubble.backgroundColor = .clear
        bubble.hasShadow = false
        bubble.ignoresMouseEvents = true
        bubble.level = .floating

        // 泡泡视图
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = Design.brandColor
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH)

        // 背景胶囊
        let bg = NSView(frame: NSRect(x: 0, y: 0, width: bubbleW, height: bubbleH))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = Design.brandColor.withAlphaComponent(0.18).cgColor
        bg.layer?.cornerRadius = bubbleH / 2

        bg.addSubview(label)
        bubble.contentView = bg

        // 定位在状态栏按钮上方
        let btnFrame = window.frame
        bubble.setFrameOrigin(NSPoint(
            x: btnFrame.midX - bubbleW / 2,
            y: btnFrame.minY - bubbleH - 8
        ))
        bubble.alphaValue = 0
        bubble.orderFrontRegardless()

        bubbleWindows.append(bubble)

        // 动画：上升 + 淡入 → 持留 → 淡出
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bubble.animator().alphaValue = 1
            let frame = bubble.frame
            bubble.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y - 30))
        }, completionHandler: { [weak self] in
            // 持留 0.8 秒后淡出
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.5
                    bubble.animator().alphaValue = 0
                    let frame = bubble.frame
                    bubble.animator().setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y - 20))
                }, completionHandler: { [weak self] in
                    bubble.orderOut(nil)
                    self?.bubbleWindows.removeAll { $0 === bubble }
                })
            }
        })
    }

    /// 标题短暂闪烁（品牌色 → 回归正常）
    func flashTitle() {
        guard let button = statusItem.button else { return }

        // 读取当前显示的文字
        let currentText = button.attributedTitle.string.isEmpty
            ? button.title
            : button.attributedTitle.string

        // 闪烁为品牌色 + 加一个 ✨
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: Design.brandColor,
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        ]
        button.attributedTitle = NSAttributedString(string: "✨ " + currentText, attributes: attrs)

        // 0.6 秒后恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            let thresholdWan = self.settings.warningThreshold
            // 恢复时用正常颜色（跟随用量色阶）
            if let stats = DataCache.shared.getCachedToday() {
                let color = Design.usageColor(total: stats.total, thresholdWan: thresholdWan)
                let normalAttrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: color,
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
                ]
                button.attributedTitle = NSAttributedString(string: self.fmtTitle(stats.total), attributes: normalAttrs)
            } else {
                let fallback: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Design.textPrimary,
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
                ]
                button.attributedTitle = NSAttributedString(string: currentText, attributes: fallback)
            }
        }
    }

    func updateIcon() {
        // 根据系统主题切换图标
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if let button = statusItem.button {
            if isDark {
                button.image = createIcon(color: NSColor.white)
            } else {
                button.image = createIcon(color: NSColor.black)
            }
        }
    }

    func createIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        let ctx = NSGraphicsContext.current!
        ctx.cgContext.setFillColor(color.cgColor)

        // 闪电形状
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 10, y: 18))
        path.line(to: NSPoint(x: 6, y: 10))
        path.line(to: NSPoint(x: 9, y: 10))
        path.line(to: NSPoint(x: 8, y: 2))
        path.line(to: NSPoint(x: 12, y: 10))
        path.line(to: NSPoint(x: 9, y: 10))
        path.close()
        path.fill()

        image.unlockFocus()
        image.isTemplate = true

        return image
    }

    func updateMenu() {
        // 使用 popover 替代 menu，此函数现在只刷新 popover 内容
        if let popover = popover, popover.isShown {
            if let viewController = popover.contentViewController as? PopoverViewController {
                viewController.viewDidLoad() // 重新加载内容
            }
        }
    }

    @objc func refreshData() {
        // 强制刷新今日和模型分布
        let todayStats = queryDayStats(days: 0)
        let modelBreakdown = queryModelBreakdown()

        // 更新缓存
        DataCache.shared.update(
            today: todayStats,
            yesterday: nil,
            week: nil,
            month: nil,
            total: nil,
            models: modelBreakdown
        )

        // 更新标题
        if let stats = todayStats {
            let totalStr = fmtTitle(stats.total)
            let thresholdWan = settings.warningThreshold
            let color = Design.usageColor(total: stats.total, thresholdWan: thresholdWan)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            ]
            statusItem.button?.attributedTitle = NSAttributedString(string: totalStr, attributes: attrs)
        }

        // 更新 popover
        updateMenu()
    }

    func fmtK(_ n: Int64) -> String {
        if n >= 100_000_000 {
            let d = Double(n) / 100_000_000
            return String(format: "%.2f亿", d)
        } else if n >= 10_000 {
            let w = n / 10_000
            return "\(w)万"
        } else {
            return "\(n)"
        }
    }

    // 格式化标题（亿保留4位小数）
    func fmtTitle(_ n: Int64) -> String {
        return Design.formatTokens(n)
    }

    // 格式化总量（亿，无小数）
    func fmtTotal(_ n: Int64) -> String {
        if n >= 100_000_000 {
            let d = Double(n) / 100_000_000
            return String(format: "%.2f亿", d)
        } else {
            return fmtK(n)
        }
    }

    @objc func copyStats() {
        var text = "ccSwitch 今日用量统计\n"
        text += "==================\n"

        if let stats = DataCache.shared.getCachedToday() {
            text += "Token 总量: \(fmtK(stats.total))\n"
            text += "请求数量: \(stats.reqs)\n"
            text += "输入 Token: \(fmtK(stats.input))\n"
            text += "输出 Token: \(fmtK(stats.output))\n"
        }

        if let models = DataCache.shared.getCachedModelBreakdown() {
            text += "\n模型分布:\n"
            for model in models {
                text += "  \(model.model): \(fmtK(model.total))\n"
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 关闭 popover 后显示提示
        closePopover()

        let alert = NSAlert()
        alert.messageText = "已复制到剪贴板"
        alert.informativeText = "统计数据已复制，可直接粘贴使用"
        alert.runModal()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings) { [weak self] in
                self?.connectDB()
                self?.startTimer()
                self?.updateData()
            }
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettingsAndClose() {
        closePopover()
        openSettings()
    }

    @objc func openDetail() {
        closePopover()
        if detailWindow == nil {
            detailWindow = DetailWindowController()
            detailWindow?.onDateChange = { [weak self] newWeekStart in
                self?.openWeekDetail(for: newWeekStart)
            }
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let weekStart = calendar.date(byAdding: .day, value: -(weekday - 2), to: today)! // 周一开始
        detailWindow?.reloadData(db: db, weekStart: weekStart)
        detailWindow?.showWindow(nil)
        detailWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openWeekDetail(for weekStart: Date) {
        if detailWindow == nil {
            detailWindow = DetailWindowController()
            detailWindow?.onDateChange = { [weak self] newWeekStart in
                self?.openWeekDetail(for: newWeekStart)
            }
        }
        detailWindow?.reloadData(db: db, weekStart: weekStart)
        detailWindow?.showWindow(nil)
        detailWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openMonthDetail() {
        closePopover()
        if monthWindow == nil {
            monthWindow = MonthDetailWindowController()
        }
        monthWindow?.db = db
        monthWindow?.currentMonth = Date()
        monthWindow?.reloadData()
        monthWindow?.showWindow(nil)
        monthWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openModelDetail(for date: Date) {
        closePopover()
        if modelWindow == nil {
            modelWindow = ModelDetailWindowController()
            modelWindow?.onDateChange = { [weak self] newDate in
                self?.openModelDetail(for: newDate)
            }
        }
        modelWindow?.db = db
        modelWindow?.reloadData(db: db, date: date)
        modelWindow?.showWindow(nil)
        modelWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openModelDetailToday() {
        openModelDetail(for: Date())
    }

    func openHourlyDetail(for date: Date) {
        closePopover()
        if hourlyWindow == nil {
            hourlyWindow = HourlyDetailWindowController()
            hourlyWindow?.onDateChange = { [weak self] newDate in
                self?.openHourlyDetail(for: newDate)
            }
        }
        currentHourlyDate = date
        hourlyWindow?.reloadData(db: db, date: date)
        hourlyWindow?.showWindow(nil)
        hourlyWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openHourlyDetailToday() {
        openHourlyDetail(for: Date())
    }

    @objc func openHourlyDetailYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        openHourlyDetail(for: yesterday)
    }

    @objc func quit() {
        closePopover()
        NSApp.terminate(nil)
    }
}

// 设置窗口
class SettingsWindowController: NSWindowController {
    let settings: Settings
    let onSave: () -> Void
    var intervalField: NSTextField!
    var pathField: NSTextField!
    var warningField: NSTextField!
    var warningCheck: NSButton!
    var launchCheck: NSButton!

    init(settings: Settings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ccBar 设置"
        window.center()
        window.backgroundColor = Design.backgroundDark

        super.init(window: window)

        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24)
        ])

        // 标题
        let titleLabel = NSTextField(labelWithString: "⚙️ 设置")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = Design.textPrimary
        stackView.addArrangedSubview(titleLabel)

        // 分隔线
        let separator1 = NSBox()
        separator1.boxType = .separator
        stackView.addArrangedSubview(separator1)
        separator1.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 刷新间隔
        let intervalRow = createSettingRow(label: "刷新间隔 (秒):", hint: "范围: 5 - 3000")
        intervalField = intervalRow.field
        stackView.addArrangedSubview(intervalRow.container)
        intervalRow.container.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 数据库路径
        let pathRow = createPathRow()
        pathField = pathRow.field
        stackView.addArrangedSubview(pathRow.container)
        pathRow.container.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 预警阈值
        let warningRow = createSettingRow(label: "预警阈值 (万):", hint: "超过此值将弹出通知提醒")
        warningField = warningRow.field
        stackView.addArrangedSubview(warningRow.container)
        warningRow.container.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 分隔线
        let separator2 = NSBox()
        separator2.boxType = .separator
        stackView.addArrangedSubview(separator2)
        separator2.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 复选框
        warningCheck = NSButton(checkboxWithTitle: "启用用量预警", target: nil, action: nil)
        warningCheck.font = NSFont.systemFont(ofSize: 13)
        stackView.addArrangedSubview(warningCheck)

        launchCheck = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
        launchCheck.font = NSFont.systemFont(ofSize: 13)
        stackView.addArrangedSubview(launchCheck)

        // 分隔线
        let separator3 = NSBox()
        separator3.boxType = .separator
        stackView.addArrangedSubview(separator3)
        separator3.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // 按钮栏
        let buttonBar = NSStackView()
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 12
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(buttonBar)
        buttonBar.trailingAnchor.constraint(equalTo: stackView.trailingAnchor).isActive = true

        let resetBtn = NSButton(title: "重置", target: self, action: #selector(resetSettings))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 13)
        buttonBar.addArrangedSubview(resetBtn)

        let saveBtn = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"  // Enter 键快捷键
        saveBtn.font = NSFont.systemFont(ofSize: 13)
        buttonBar.addArrangedSubview(saveBtn)
    }

    private func createSettingRow(label: String, hint: String) -> (container: NSView, field: NSTextField) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let labelField = NSTextField(labelWithString: label)
        labelField.font = NSFont.systemFont(ofSize: 13)
        labelField.textColor = Design.textPrimary
        labelField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(labelField)

        let field = NSTextField()
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = Design.textPrimary
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)

        let hintField = NSTextField(labelWithString: hint)
        hintField.font = NSFont.systemFont(ofSize: 11)
        hintField.textColor = Design.textMuted
        hintField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hintField)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelField.topAnchor.constraint(equalTo: container.topAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 120),

            field.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 8),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.widthAnchor.constraint(equalToConstant: 100),

            hintField.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            hintField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            hintField.centerYAnchor.constraint(equalTo: field.centerYAnchor)
        ])

        container.heightAnchor.constraint(equalToConstant: 22).isActive = true

        return (container, field)
    }

    private func createPathRow() -> (container: NSView, field: NSTextField) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let labelField = NSTextField(labelWithString: "数据库路径:")
        labelField.font = NSFont.systemFont(ofSize: 13)
        labelField.textColor = Design.textPrimary
        labelField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(labelField)

        let field = NSTextField()
        field.font = NSFont.systemFont(ofSize: 13)
        field.textColor = Design.textPrimary
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)

        let browseBtn = NSButton(title: "浏览", target: self, action: #selector(browsePath))
        browseBtn.bezelStyle = .rounded
        browseBtn.font = NSFont.systemFont(ofSize: 12)
        browseBtn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(browseBtn)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            labelField.topAnchor.constraint(equalTo: container.topAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 120),

            field.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 8),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.trailingAnchor.constraint(equalTo: browseBtn.leadingAnchor, constant: -8),

            browseBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            browseBtn.topAnchor.constraint(equalTo: container.topAnchor),
            browseBtn.widthAnchor.constraint(equalToConstant: 60)
        ])

        container.heightAnchor.constraint(equalToConstant: 22).isActive = true

        return (container, field)
    }

    func loadSettings() {
        intervalField.stringValue = "\(settings.refreshInterval)"
        pathField.stringValue = settings.dbPath
        pathField.toolTip = settings.dbPath
        warningField.stringValue = "\(settings.warningThreshold)"
        warningCheck.state = settings.warningEnabled ? .on : .off
        launchCheck.state = settings.launchAtLogin ? .on : .off
    }

    @objc func browsePath() {
        let panel = NSOpenPanel()
        panel.title = "选择数据库文件"
        panel.allowedFileTypes = ["db"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url {
                self?.pathField.stringValue = url.path
                self?.pathField.toolTip = url.path
            }
        }
    }

    @objc func saveSettings() {
        if let interval = Int(intervalField.stringValue), interval >= 5 && interval <= 3000 {
            settings.refreshInterval = interval
        }
        settings.dbPath = pathField.stringValue
        if let threshold = Int(warningField.stringValue), threshold > 0 {
            settings.warningThreshold = threshold
        }
        settings.warningEnabled = warningCheck.state == .on
        settings.launchAtLogin = launchCheck.state == .on

        let alert = NSAlert()
        alert.messageText = "设置已保存"
        alert.informativeText = "新的设置将在下次刷新时生效"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()

        onSave()
        window?.close()
    }

    @objc func resetSettings() {
        settings.refreshInterval = 30
        settings.dbPath = "\(NSHomeDirectory())/.cc-switch/cc-switch.db"
        settings.warningThreshold = 50
        settings.warningEnabled = true
        settings.launchAtLogin = false
        loadSettings()
    }
}

// 7天详情窗口（按周导航）
class DetailWindowController: NSWindowController {
    var contentStack: NSStackView!
    var dateLabel: NSTextField!
    var currentWeekStart: Date = Date()
    var onDateChange: ((Date) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "近7天用量"
        window.center()
        window.backgroundColor = Design.backgroundDark
        window.minSize = NSSize(width: 450, height: 250)
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 顶部导航栏
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            navBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            navBar.heightAnchor.constraint(equalToConstant: 32)
        ])

        let prevBtn = NSButton(title: "◀", target: self, action: #selector(prevWeek))
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.bezelStyle = .inline
        prevBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(prevBtn)

        dateLabel = NSTextField(labelWithString: "")
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        dateLabel.textColor = Design.textPrimary
        dateLabel.alignment = .center
        navBar.addSubview(dateLabel)

        let nextBtn = NSButton(title: "▶", target: self, action: #selector(nextWeek))
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.bezelStyle = .inline
        nextBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(nextBtn)

        NSLayoutConstraint.activate([
            prevBtn.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            prevBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            prevBtn.widthAnchor.constraint(equalToConstant: 30),
            dateLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            nextBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.widthAnchor.constraint(equalToConstant: 30)
        ])

        // 直接使用栈视图，不需要滚动
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @objc func prevWeek() {
        currentWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: currentWeekStart)!
        onDateChange?(currentWeekStart)
    }

    @objc func nextWeek() {
        let nextStart = Calendar.current.date(byAdding: .day, value: 7, to: currentWeekStart)!
        if nextStart <= Date() {
            currentWeekStart = nextStart
            onDateChange?(currentWeekStart)
        }
    }

    func createRow(date: String, reqs: Int, totalToken: Int64, cacheRead: Int64, isBold: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: isBold ? 26 : 22).isActive = true

        let dateField = NSTextField(labelWithString: date)
        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .semibold)
        dateField.textColor = isBold ? NSColor.white : NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        container.addSubview(dateField)

        let reqsField = NSTextField(labelWithString: reqs == 0 ? "-" : "\(reqs)次")
        reqsField.translatesAutoresizingMaskIntoConstraints = false
        reqsField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        reqsField.textColor = reqs == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        reqsField.alignment = .right
        container.addSubview(reqsField)

        let totalField = NSTextField(labelWithString: fmtNum(totalToken))
        totalField.translatesAutoresizingMaskIntoConstraints = false
        totalField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        totalField.textColor = totalToken == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        totalField.alignment = .right
        container.addSubview(totalField)

        let cacheField = NSTextField(labelWithString: fmtNum(cacheRead))
        cacheField.translatesAutoresizingMaskIntoConstraints = false
        cacheField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        cacheField.textColor = cacheRead == 0 ? NSColor(white: 0.4, alpha: 1.0) : (isBold ? NSColor.white : NSColor(white: 0.7, alpha: 1.0))
        cacheField.alignment = .right
        container.addSubview(cacheField)

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dateField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dateField.widthAnchor.constraint(equalToConstant: 70),
            reqsField.leadingAnchor.constraint(equalTo: dateField.trailingAnchor, constant: 8),
            reqsField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            reqsField.widthAnchor.constraint(equalToConstant: 70),
            totalField.leadingAnchor.constraint(equalTo: reqsField.trailingAnchor, constant: 8),
            totalField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            totalField.widthAnchor.constraint(equalToConstant: 100),
            cacheField.leadingAnchor.constraint(equalTo: totalField.trailingAnchor, constant: 8),
            cacheField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            cacheField.widthAnchor.constraint(equalToConstant: 100),
            cacheField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func createHeaderRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let labels = ["日期", "请求数", "总token", "缓存读"]
        let widths: [CGFloat] = [70, 70, 100, 100]
        var leadingAnchor = container.leadingAnchor

        for (index, text) in labels.enumerated() {
            let label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = Design.textMuted
            label.alignment = index == 0 ? .left : .right
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: index == 0 ? 0 : 8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: widths[index])
            ])

            if index < labels.count - 1 {
                leadingAnchor = label.trailingAnchor
            }
        }

        return container
    }

    func createSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.borderColor = NSColor(white: 0.25, alpha: 1.0)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    func fmtNum(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.1f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else if n == 0 {
            return "-"
        } else {
            return "\(n)"
        }
    }

    func reloadData(db: OpaquePointer?, weekStart: Date) {
        guard let db = db else { return }

        currentWeekStart = weekStart

        // 更新日期标签
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd"
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 6, to: weekStart)!
        dateLabel.stringValue = "\(formatter.string(from: weekStart)) ~ \(formatter.string(from: endOfWeek))"

        // 计算每天距今的天数
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 清空旧内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 添加 sparkline 趋势图
        let chartContainer = NSView()
        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.heightAnchor.constraint(equalToConstant: 60).isActive = true
        contentStack.addArrangedSubview(chartContainer)
        chartContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 7天数据
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0
        var dailyTokens: [CGFloat] = []  // 用于 sparkline

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let daysAgo = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0

            // 查询该天数据（先查原始日志，没有则查汇总）
            var reqs = 0
            var output: Int64 = 0
            var input: Int64 = 0
            var cacheRead: Int64 = 0

            let sql = """
            SELECT SUM(reqs), SUM(output), SUM(input), SUM(cache_read) FROM (
                SELECT COUNT(*) as reqs,
                    COALESCE(SUM(output_tokens), 0) as output,
                    COALESCE(SUM(input_tokens), 0) as input,
                    COALESCE(SUM(cache_read_tokens), 0) as cache_read
                FROM proxy_request_logs
                WHERE date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime', '-' || ? || ' days')
                UNION ALL
                SELECT COALESCE(SUM(request_count), 0) as reqs,
                    COALESCE(SUM(output_tokens), 0) as output,
                    COALESCE(SUM(input_tokens), 0) as input,
                    COALESCE(SUM(cache_read_tokens), 0) as cache_read
                FROM usage_daily_rollups
                WHERE date = date('now', 'localtime', '-' || ? || ' days')
                  AND date < (SELECT date(MIN(created_at), 'unixepoch', 'localtime') FROM proxy_request_logs)
            )
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(daysAgo))
                sqlite3_bind_int(stmt, 2, Int32(daysAgo))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    reqs = Int(sqlite3_column_int(stmt, 0))
                    output = sqlite3_column_int64(stmt, 1)
                    input = sqlite3_column_int64(stmt, 2)
                    cacheRead = sqlite3_column_int64(stmt, 3)
                }
            }
            sqlite3_finalize(stmt)

            let dayToken = output + input + cacheRead
            totalReqs += reqs
            totalToken += dayToken
            totalCacheRead += cacheRead

            // 日期格式：MM/dd
            let dateStr = formatter.string(from: date)
            let row = createRow(date: dateStr, reqs: reqs, totalToken: dayToken, cacheRead: cacheRead)
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

            // 收集数据用于 sparkline
            dailyTokens.append(CGFloat(dayToken))
        }

        // 创建 sparkline 趋势图
        let sparkline = SparklineView(frame: NSRect(x: 8, y: 8, width: 400, height: 44))
        sparkline.values = dailyTokens
        sparkline.useGradient = true
        // 按周次偏移色相，翻到不同周颜色会变化
        let weekOfYear = calendar.ordinality(of: .weekOfYear, in: .year, for: weekStart) ?? 0
        sparkline.hueOffset = CGFloat(weekOfYear % 8) / 8.0
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.addSubview(sparkline)

        NSLayoutConstraint.activate([
            sparkline.topAnchor.constraint(equalTo: chartContainer.topAnchor, constant: 8),
            sparkline.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor, constant: 8),
            sparkline.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor, constant: -8),
            sparkline.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor, constant: -8)
        ])

        // 合计行
        contentStack.addArrangedSubview(createSeparator())
        let totalRow = createRow(date: "合计", reqs: totalReqs, totalToken: totalToken, cacheRead: totalCacheRead, isBold: true)
        contentStack.addArrangedSubview(totalRow)
        totalRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        window?.setContentSize(NSSize(width: 550, height: 350))
    }
}

// 30天详情窗口（按月导航）
class MonthDetailWindowController: NSWindowController {
    var contentStack: NSStackView!
    var dateLabel: NSTextField!
    var currentMonth: Date = Date()
    var db: OpaquePointer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "近30天用量"
        window.center()
        window.backgroundColor = Design.backgroundDark
        window.minSize = NSSize(width: 450, height: 300)
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            navBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            navBar.heightAnchor.constraint(equalToConstant: 32)
        ])

        let prevBtn = NSButton(title: "◀", target: self, action: #selector(prevMonth))
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.bezelStyle = .inline
        prevBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(prevBtn)

        dateLabel = NSTextField(labelWithString: "")
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        dateLabel.textColor = Design.textPrimary
        dateLabel.alignment = .center
        navBar.addSubview(dateLabel)

        let nextBtn = NSButton(title: "▶", target: self, action: #selector(nextMonth))
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.bezelStyle = .inline
        nextBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(nextBtn)

        NSLayoutConstraint.activate([
            prevBtn.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            prevBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            prevBtn.widthAnchor.constraint(equalToConstant: 30),
            dateLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            nextBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.widthAnchor.constraint(equalToConstant: 30)
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 0),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 2
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.documentView = contentStack
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: clipView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: clipView.trailingAnchor)
        ])
    }

    @objc func prevMonth() {
        currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
        reloadData()
    }

    @objc func nextMonth() {
        let nextMonthDate = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
        if nextMonthDate <= Date() {
            currentMonth = nextMonthDate
            reloadData()
        }
    }

    func createRow(date: String, reqs: Int, totalToken: Int64, cacheRead: Int64, isBold: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: isBold ? 30 : 26).isActive = true

        let dateField = NSTextField(labelWithString: date)
        dateField.translatesAutoresizingMaskIntoConstraints = false
        dateField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .semibold)
        dateField.textColor = isBold ? NSColor.white : NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        container.addSubview(dateField)

        let reqsField = NSTextField(labelWithString: reqs == 0 ? "-" : "\(reqs)次")
        reqsField.translatesAutoresizingMaskIntoConstraints = false
        reqsField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        reqsField.textColor = reqs == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        reqsField.alignment = .right
        container.addSubview(reqsField)

        let totalField = NSTextField(labelWithString: fmtNum(totalToken))
        totalField.translatesAutoresizingMaskIntoConstraints = false
        totalField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        totalField.textColor = totalToken == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        totalField.alignment = .right
        container.addSubview(totalField)

        let cacheField = NSTextField(labelWithString: fmtNum(cacheRead))
        cacheField.translatesAutoresizingMaskIntoConstraints = false
        cacheField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        cacheField.textColor = cacheRead == 0 ? NSColor(white: 0.4, alpha: 1.0) : (isBold ? NSColor.white : NSColor(white: 0.7, alpha: 1.0))
        cacheField.alignment = .right
        container.addSubview(cacheField)

        NSLayoutConstraint.activate([
            dateField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dateField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dateField.widthAnchor.constraint(equalToConstant: 70),
            reqsField.leadingAnchor.constraint(equalTo: dateField.trailingAnchor, constant: 8),
            reqsField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            reqsField.widthAnchor.constraint(equalToConstant: 70),
            totalField.leadingAnchor.constraint(equalTo: reqsField.trailingAnchor, constant: 8),
            totalField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            totalField.widthAnchor.constraint(equalToConstant: 100),
            cacheField.leadingAnchor.constraint(equalTo: totalField.trailingAnchor, constant: 8),
            cacheField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            cacheField.widthAnchor.constraint(equalToConstant: 100),
            cacheField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func createHeaderRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let labels = ["日期", "请求数", "总token", "缓存读"]
        let widths: [CGFloat] = [70, 70, 100, 100]
        var leadingAnchor = container.leadingAnchor

        for (index, text) in labels.enumerated() {
            let label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = Design.textMuted
            label.alignment = index == 0 ? .left : .right
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: index == 0 ? 0 : 8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: widths[index])
            ])

            if index < labels.count - 1 {
                leadingAnchor = label.trailingAnchor
            }
        }

        return container
    }

    func createSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.borderColor = NSColor(white: 0.25, alpha: 1.0)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    func fmtNum(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.1f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else if n == 0 {
            return "-"
        } else {
            return "\(n)"
        }
    }

    func reloadData() {
        // 更新日期标签
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM"
        dateLabel.stringValue = formatter.string(from: currentMonth)

        // 如果没有 db 连接，不加载数据
        guard let db = self.db else { return }

        // 计算月份的第一天和天数
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: currentMonth)
        let firstOfMonth = calendar.date(from: components)!
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!.count

        // 清空旧内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // 添加折线图容器（整月的日趋势）
        let chartContainer = NSView()
        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.heightAnchor.constraint(equalToConstant: 70).isActive = true
        contentStack.addArrangedSubview(chartContainer)
        chartContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 本月每天数据
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0
        var dailyTokens: [CGFloat] = []  // 用于折线图

        let today = calendar.startOfDay(for: Date())

        for day in 1...daysInMonth {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            
            // 跳过未来的日期
            if dayStart > today { break }

            let daysAgo = calendar.dateComponents([.day], from: dayStart, to: today).day ?? 0

            // 查询该天数据（先查原始日志，没有则查汇总）
            var reqs = 0
            var output: Int64 = 0
            var input: Int64 = 0
            var cacheRead: Int64 = 0

            let sql = """
            SELECT SUM(reqs), SUM(output), SUM(input), SUM(cache_read) FROM (
                SELECT COUNT(*) as reqs,
                    COALESCE(SUM(output_tokens), 0) as output,
                    COALESCE(SUM(input_tokens), 0) as input,
                    COALESCE(SUM(cache_read_tokens), 0) as cache_read
                FROM proxy_request_logs
                WHERE date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime', '-' || ? || ' days')
                UNION ALL
                SELECT COALESCE(SUM(request_count), 0) as reqs,
                    COALESCE(SUM(output_tokens), 0) as output,
                    COALESCE(SUM(input_tokens), 0) as input,
                    COALESCE(SUM(cache_read_tokens), 0) as cache_read
                FROM usage_daily_rollups
                WHERE date = date('now', 'localtime', '-' || ? || ' days')
                  AND date < (SELECT date(MIN(created_at), 'unixepoch', 'localtime') FROM proxy_request_logs)
            )
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(daysAgo))
                sqlite3_bind_int(stmt, 2, Int32(daysAgo))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    reqs = Int(sqlite3_column_int(stmt, 0))
                    output = sqlite3_column_int64(stmt, 1)
                    input = sqlite3_column_int64(stmt, 2)
                    cacheRead = sqlite3_column_int64(stmt, 3)
                }
            }
            sqlite3_finalize(stmt)

            let dayToken = output + input + cacheRead
            totalReqs += reqs
            totalToken += dayToken
            totalCacheRead += cacheRead

            let dateStr = String(format: "%02d/%02d", components.month!, day)
            let row = createRow(date: dateStr, reqs: reqs, totalToken: dayToken, cacheRead: cacheRead)
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

            // 收集数据用于折线图
            dailyTokens.append(CGFloat(dayToken))
        }

        // 创建折线图（整月趋势）
        let sparkline = SparklineView(frame: NSRect(x: 8, y: 8, width: 400, height: 54))
        sparkline.values = dailyTokens
        sparkline.useGradient = true
        // 按月偏移色相，翻到不同月份颜色会变化
        if let month = components.month {
            sparkline.hueOffset = CGFloat((month * 3) % 8) / 8.0
        }
        sparkline.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.addSubview(sparkline)

        NSLayoutConstraint.activate([
            sparkline.topAnchor.constraint(equalTo: chartContainer.topAnchor, constant: 8),
            sparkline.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor, constant: 8),
            sparkline.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor, constant: -8),
            sparkline.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor, constant: -8)
        ])

        // 合计行
        contentStack.addArrangedSubview(createSeparator())
        let totalRow = createRow(date: "合计", reqs: totalReqs, totalToken: totalToken, cacheRead: totalCacheRead, isBold: true)
        contentStack.addArrangedSubview(totalRow)
        totalRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }
}

// 模型分布详情窗口
class ModelDetailWindowController: NSWindowController {
    var contentStack: NSStackView!
    var dateLabel: NSTextField!
    var currentDate: Date = Date()
    var onDateChange: ((Date) -> Void)?
    var db: OpaquePointer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "模型分布详情"
        window.center()
        window.backgroundColor = Design.backgroundDark
        window.minSize = NSSize(width: 500, height: 300)
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 顶部导航栏
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            navBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            navBar.heightAnchor.constraint(equalToConstant: 32)
        ])

        let prevBtn = NSButton(title: "◀", target: self, action: #selector(prevDay))
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.bezelStyle = .inline
        prevBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(prevBtn)

        dateLabel = NSTextField(labelWithString: "")
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        dateLabel.textColor = Design.textPrimary
        dateLabel.alignment = .center
        navBar.addSubview(dateLabel)

        let nextBtn = NSButton(title: "▶", target: self, action: #selector(nextDay))
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.bezelStyle = .inline
        nextBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(nextBtn)

        NSLayoutConstraint.activate([
            prevBtn.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            prevBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            prevBtn.widthAnchor.constraint(equalToConstant: 30),
            dateLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            nextBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.widthAnchor.constraint(equalToConstant: 30)
        ])

        // 直接使用栈视图，不需要滚动
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @objc func prevDay() {
        currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate)!
        onDateChange?(currentDate)
    }

    @objc func nextDay() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
        if tomorrow <= Date() {
            currentDate = tomorrow
            onDateChange?(currentDate)
        }
    }

    func createRow(model: String, reqs: Int, totalToken: Int64, cacheRead: Int64, isBold: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: isBold ? 28 : 24).isActive = true

        let modelField = NSTextField(labelWithString: model)
        modelField.translatesAutoresizingMaskIntoConstraints = false
        modelField.font = NSFont.systemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        modelField.textColor = isBold ? NSColor.white : NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        modelField.maximumNumberOfLines = 1
        modelField.lineBreakMode = .byTruncatingTail
        container.addSubview(modelField)

        let reqsField = NSTextField(labelWithString: reqs == 0 ? "-" : "\(reqs)次")
        reqsField.translatesAutoresizingMaskIntoConstraints = false
        reqsField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        reqsField.textColor = reqs == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        reqsField.alignment = .right
        container.addSubview(reqsField)

        let totalField = NSTextField(labelWithString: fmtNum(totalToken))
        totalField.translatesAutoresizingMaskIntoConstraints = false
        totalField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        totalField.textColor = totalToken == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        totalField.alignment = .right
        container.addSubview(totalField)

        let cacheField = NSTextField(labelWithString: fmtNum(cacheRead))
        cacheField.translatesAutoresizingMaskIntoConstraints = false
        cacheField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        cacheField.textColor = cacheRead == 0 ? NSColor(white: 0.4, alpha: 1.0) : (isBold ? NSColor.white : NSColor(white: 0.7, alpha: 1.0))
        cacheField.alignment = .right
        container.addSubview(cacheField)

        NSLayoutConstraint.activate([
            modelField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            modelField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            modelField.widthAnchor.constraint(equalToConstant: 200),

            reqsField.leadingAnchor.constraint(equalTo: modelField.trailingAnchor, constant: 8),
            reqsField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            reqsField.widthAnchor.constraint(equalToConstant: 80),

            totalField.leadingAnchor.constraint(equalTo: reqsField.trailingAnchor, constant: 8),
            totalField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            totalField.widthAnchor.constraint(equalToConstant: 120),

            cacheField.leadingAnchor.constraint(equalTo: totalField.trailingAnchor, constant: 8),
            cacheField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            cacheField.widthAnchor.constraint(equalToConstant: 120),
            cacheField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func createHeaderRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let labels = ["模型", "请求数", "总token", "缓存读"]
        let widths: [CGFloat] = [200, 80, 120, 120]
        var leadingAnchor = container.leadingAnchor

        for (index, text) in labels.enumerated() {
            let label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = Design.textMuted
            label.alignment = index == 0 ? .left : .right
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: index == 0 ? 0 : 8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: widths[index])
            ])

            if index < labels.count - 1 {
                leadingAnchor = label.trailingAnchor
            }
        }

        return container
    }

    func createSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.borderColor = NSColor(white: 0.25, alpha: 1.0)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    func fmtNum(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.1f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else if n == 0 {
            return "-"
        } else {
            return "\(n)"
        }
    }

    func reloadData(db: OpaquePointer?, date: Date) {
        guard let db = db else { return }

        currentDate = date

        // 更新日期标签
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd"
        dateLabel.stringValue = formatter.string(from: date)

        // 计算 daysAgo
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: targetDay, to: today).day ?? 0

        // 查询模型分布
        let sql = """
        SELECT
            model,
            COUNT(*) as reqs,
            COALESCE(SUM(input_tokens + output_tokens + cache_read_tokens + cache_creation_tokens), 0) as total_token,
            COALESCE(SUM(cache_read_tokens), 0) as cache_read
        FROM proxy_request_logs
        WHERE date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime', '-' || ? || ' days')
        GROUP BY model
        ORDER BY total_token DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(stmt, 1, Int32(daysAgo))

        var models: [(model: String, reqs: Int, totalToken: Int64, cacheRead: Int64)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let reqs = Int(sqlite3_column_int(stmt, 1))
            let totalToken = sqlite3_column_int64(stmt, 2)
            let cacheRead = sqlite3_column_int64(stmt, 3)
            models.append((model, reqs, totalToken, cacheRead))
        }
        sqlite3_finalize(stmt)

        // 清空旧内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if models.isEmpty {
            let noDataLabel = NSTextField(labelWithString: "暂无数据")
            noDataLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            noDataLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
            contentStack.addArrangedSubview(noDataLabel)
            return
        }

        // 计算合计
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0
        for model in models {
            totalReqs += model.reqs
            totalToken += model.totalToken
            totalCacheRead += model.cacheRead
        }

        // 添加环形图
        let chartContainer = NSView()
        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.heightAnchor.constraint(equalToConstant: 150).isActive = true
        contentStack.addArrangedSubview(chartContainer)
        chartContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        let donutView = DonutChartWithLegendView(frame: NSRect(x: 0, y: 0, width: 500, height: 150))
        // 与主页模型分布使用同一套配色（按小时轮换）
        let colors = Design.modelColors()
        donutView.items = models.prefix(6).enumerated().map { index, model in
            let percentage = totalToken > 0 ? String(format: "%.1f%%", Double(model.totalToken) / Double(totalToken) * 100) : "0%"
            let shortName = model.model.count > 12 ? String(model.model.prefix(12)) + "..." : model.model
            return DonutChartWithLegendView.Item(
                value: CGFloat(model.totalToken),
                color: colors[index % colors.count],
                label: shortName,
                percentage: percentage
            )
        }
        donutView.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.addSubview(donutView)

        NSLayoutConstraint.activate([
            donutView.topAnchor.constraint(equalTo: chartContainer.topAnchor),
            donutView.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor),
            donutView.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor),
            donutView.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor)
        ])

        contentStack.addArrangedSubview(createSeparator())

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 数据行
        for model in models {
            let row = createRow(
                model: model.model,
                reqs: model.reqs,
                totalToken: model.totalToken,
                cacheRead: model.cacheRead
            )
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        // 合计行
        contentStack.addArrangedSubview(createSeparator())
        let totalRow = createRow(model: "合计", reqs: totalReqs, totalToken: totalToken, cacheRead: totalCacheRead, isBold: true)
        contentStack.addArrangedSubview(totalRow)
        totalRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }
}

// 每小时详情窗口
class HourlyDetailWindowController: NSWindowController {
    var contentStack: NSStackView!
    var dateLabel: NSTextField!
    var currentDate: Date = Date()
    var onDateChange: ((Date) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "日志"
        window.center()
        window.backgroundColor = Design.backgroundDark
        window.minSize = NSSize(width: 350, height: 300)
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        // 顶部导航栏
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(navBar)

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            navBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            navBar.heightAnchor.constraint(equalToConstant: 32)
        ])

        // 前一天按钮
        let prevBtn = NSButton(title: "◀", target: self, action: #selector(prevDay))
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.bezelStyle = .inline
        prevBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(prevBtn)

        // 日期标签
        dateLabel = NSTextField(labelWithString: "")
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        dateLabel.textColor = Design.textPrimary
        dateLabel.alignment = .center
        navBar.addSubview(dateLabel)

        // 后一天按钮
        let nextBtn = NSButton(title: "▶", target: self, action: #selector(nextDay))
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.bezelStyle = .inline
        nextBtn.font = NSFont.systemFont(ofSize: 14)
        navBar.addSubview(nextBtn)

        NSLayoutConstraint.activate([
            prevBtn.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            prevBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            prevBtn.widthAnchor.constraint(equalToConstant: 30),

            dateLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            nextBtn.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            nextBtn.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            nextBtn.widthAnchor.constraint(equalToConstant: 30)
        ])

        // 直接使用栈视图，不需要滚动
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 4),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    @objc func prevDay() {
        currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate)!
        onDateChange?(currentDate)
    }

    @objc func nextDay() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDate)!
        if tomorrow <= Date() {
            currentDate = tomorrow
            onDateChange?(currentDate)
        }
    }

    func createRow(hour: String, reqs: Int, totalToken: Int64, cacheRead: Int64, isBold: Bool = false) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: isBold ? 28 : 24).isActive = true

        let hourField = NSTextField(labelWithString: hour)
        hourField.translatesAutoresizingMaskIntoConstraints = false
        hourField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .semibold)
        hourField.textColor = isBold ? NSColor.white : NSColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        container.addSubview(hourField)

        let reqsField = NSTextField(labelWithString: reqs == 0 ? "-" : "\(reqs)次")
        reqsField.translatesAutoresizingMaskIntoConstraints = false
        reqsField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        reqsField.textColor = reqs == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        reqsField.alignment = .right
        container.addSubview(reqsField)

        let totalField = NSTextField(labelWithString: fmtNum(totalToken))
        totalField.translatesAutoresizingMaskIntoConstraints = false
        totalField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        totalField.textColor = totalToken == 0 ? NSColor(white: 0.4, alpha: 1.0) : NSColor.white
        totalField.alignment = .right
        container.addSubview(totalField)

        let cacheField = NSTextField(labelWithString: fmtNum(cacheRead))
        cacheField.translatesAutoresizingMaskIntoConstraints = false
        cacheField.font = NSFont.monospacedDigitSystemFont(ofSize: isBold ? 12 : 11, weight: isBold ? .bold : .medium)
        cacheField.textColor = cacheRead == 0 ? NSColor(white: 0.4, alpha: 1.0) : (isBold ? NSColor.white : NSColor(white: 0.7, alpha: 1.0))
        cacheField.alignment = .right
        container.addSubview(cacheField)

        NSLayoutConstraint.activate([
            hourField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hourField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hourField.widthAnchor.constraint(equalToConstant: 50),

            reqsField.leadingAnchor.constraint(equalTo: hourField.trailingAnchor, constant: 8),
            reqsField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            reqsField.widthAnchor.constraint(equalToConstant: 70),

            totalField.leadingAnchor.constraint(equalTo: reqsField.trailingAnchor, constant: 8),
            totalField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            totalField.widthAnchor.constraint(equalToConstant: 100),

            cacheField.leadingAnchor.constraint(equalTo: totalField.trailingAnchor, constant: 8),
            cacheField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            cacheField.widthAnchor.constraint(equalToConstant: 100),
            cacheField.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        return container
    }

    func createHeaderRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let labels = ["时间", "请求数", "总token", "缓存读"]
        let widths: [CGFloat] = [50, 70, 100, 100]
        var leadingAnchor = container.leadingAnchor

        for (index, text) in labels.enumerated() {
            let label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = Design.textMuted
            label.alignment = index == 0 ? .left : .right
            container.addSubview(label)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: index == 0 ? 0 : 8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: widths[index])
            ])

            if index < labels.count - 1 {
                leadingAnchor = label.trailingAnchor
            }
        }

        return container
    }

    func createSeparator() -> NSView {
        let sep = NSBox()
        sep.boxType = .separator
        sep.borderColor = NSColor(white: 0.25, alpha: 1.0)
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    func fmtNum(_ n: Int64) -> String {
        if n >= 100_000_000 {
            return String(format: "%.1f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return "\(n / 10_000)万"
        } else if n == 0 {
            return "-"
        } else {
            return "\(n)"
        }
    }

    func reloadData(db: OpaquePointer?, date: Date) {
        guard let db = db else { return }

        currentDate = date

        // 更新日期标签 (YY-MM-DD格式)
        let formatter = DateFormatter()
        formatter.dateFormat = "yy-MM-dd"
        dateLabel.stringValue = formatter.string(from: date)

        // 计算 daysAgo
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDay = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: targetDay, to: today).day ?? 0

        // 初始化24小时数据为0
        var hourlyData: [(reqs: Int, output: Int64, input: Int64, cacheRead: Int64)] = Array(repeating: (0, 0, 0, 0), count: 24)

        let sql = """
        SELECT
            strftime('%H', created_at, 'unixepoch', 'localtime') as hour,
            COUNT(*) as reqs,
            COALESCE(SUM(output_tokens), 0) as output,
            COALESCE(SUM(input_tokens), 0) as input,
            COALESCE(SUM(cache_read_tokens), 0) as cache_read
        FROM proxy_request_logs
        WHERE date(created_at, 'unixepoch', 'localtime') = date('now', 'localtime', '-' || ? || ' days')
        GROUP BY hour
        ORDER BY hour
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int(stmt, 1, Int32(daysAgo))

        var hasData = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hour = Int(String(cString: sqlite3_column_text(stmt, 0))) ?? 0
            let reqs = Int(sqlite3_column_int(stmt, 1))
            let output = sqlite3_column_int64(stmt, 2)
            let input = sqlite3_column_int64(stmt, 3)
            let cacheRead = sqlite3_column_int64(stmt, 4)
            if hour >= 0 && hour < 24 {
                hourlyData[hour] = (reqs, output, input, cacheRead)
                if reqs > 0 { hasData = true }
            }
        }
        sqlite3_finalize(stmt)

        // 清空旧内容
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if !hasData {
            let noDataLabel = NSTextField(labelWithString: "暂无数据")
            noDataLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            noDataLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
            contentStack.addArrangedSubview(noDataLabel)
            return
        }

        // 找有数据的范围
        var startHour = 0
        var endHour = 23
        for hour in 0..<24 {
            if hourlyData[hour].reqs > 0 {
                startHour = hour
                break
            }
        }
        for hour in stride(from: 23, through: 0, by: -1) {
            if hourlyData[hour].reqs > 0 {
                endHour = hour
                break
            }
        }

        // 添加柱状图
        let chartContainer = NSView()
        chartContainer.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.heightAnchor.constraint(equalToConstant: 100).isActive = true
        contentStack.addArrangedSubview(chartContainer)
        chartContainer.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        let barChart = BarChartView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        barChart.values = (startHour...endHour).map { CGFloat(hourlyData[$0].reqs) }
        barChart.labels = (startHour...endHour).map { "\($0)" }
        barChart.useGradient = true
        // 每天用不同的起始色，避免每天看起来都一样
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        barChart.hueOffset = CGFloat(dayOfYear % 6) / 6.0
        barChart.translatesAutoresizingMaskIntoConstraints = false
        chartContainer.addSubview(barChart)

        NSLayoutConstraint.activate([
            barChart.topAnchor.constraint(equalTo: chartContainer.topAnchor),
            barChart.leadingAnchor.constraint(equalTo: chartContainer.leadingAnchor),
            barChart.trailingAnchor.constraint(equalTo: chartContainer.trailingAnchor),
            barChart.bottomAnchor.constraint(equalTo: chartContainer.bottomAnchor)
        ])

        contentStack.addArrangedSubview(createSeparator())

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 计算当天总用量
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0
        for hour in startHour...endHour {
            let data = hourlyData[hour]
            totalReqs += data.reqs
            totalToken += data.output + data.input + data.cacheRead
            totalCacheRead += data.cacheRead
        }

        // 总计行（加粗显示）
        let totalRow = createRow(hour: "合计", reqs: totalReqs, totalToken: totalToken, cacheRead: totalCacheRead, isBold: true)
        contentStack.addArrangedSubview(totalRow)
        totalRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 数据行
        for hour in startHour...endHour {
            let data = hourlyData[hour]
            let totalToken = data.output + data.input + data.cacheRead
            let row = createRow(
                hour: "\(hour)时",
                reqs: data.reqs,
                totalToken: totalToken,
                cacheRead: data.cacheRead
            )
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        // 调整窗口高度
        let contentHeight = CGFloat(endHour - startHour + 2) * 24 + 80
        window?.setContentSize(NSSize(width: 450, height: min(contentHeight, 600)))
    }
}

// 主程序
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
