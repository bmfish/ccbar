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

/// Sparkline 小图表
class SparklineView: NSView {
    var values: [CGFloat] = []
    var lineColor: NSColor = Design.brandColor
    var fillColor: NSColor = Design.brandColor.withAlphaComponent(0.15)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard values.count > 1 else { return }

        let maxVal = values.max() ?? 1
        let minVal = values.min() ?? 0
        let range = maxVal - minVal

        let stepX = bounds.width / CGFloat(values.count - 1)
        let padding: CGFloat = 2
        let availableHeight = bounds.height - padding * 2

        // 计算点
        var points: [NSPoint] = []
        for (i, val) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let normalized = range > 0 ? (val - minVal) / range : 0.5
            let y = padding + normalized * availableHeight
            points.append(NSPoint(x: x, y: y))
        }

        // 绘制填充区域
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: points[0].x, y: padding))
        for point in points {
            fillPath.line(to: point)
        }
        fillPath.line(to: NSPoint(x: points.last!.x, y: padding))
        fillPath.close()
        fillColor.setFill()
        fillPath.fill()

        // 绘制线条
        let linePath = NSBezierPath()
        linePath.lineWidth = 1.5
        linePath.lineJoinStyle = .round
        linePath.lineCapStyle = .round
        linePath.move(to: points[0])
        for point in points.dropFirst() {
            linePath.line(to: point)
        }
        lineColor.setStroke()
        linePath.stroke()

        // 绘制终点圆点
        if let lastPoint = points.last {
            let dotRadius: CGFloat = 3
            let dotRect = NSRect(x: lastPoint.x - dotRadius, y: lastPoint.y - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2)
            let dotPath = NSBezierPath(ovalIn: dotRect)
            lineColor.setFill()
            dotPath.fill()
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

class AppDelegate: NSObject, NSApplicationDelegate {
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 初始数据库连接
        connectDB()

        // 初始化历史备份表
        initHistoryTable()

        // 备份历史数据（启动时执行一次）
        backupHistory()

        // 初始更新
        updateData()

        // 定时器
        startTimer()
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

        // 更新标题
        if let stats = todayStats {
            let totalStr = fmtTitle(stats.total)
            statusItem.button?.title = totalStr

            // 检查预警
            checkWarning(stats: stats)
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
        let menu = NSMenu()

        // 设置菜单使用深色模式以提高对比度
        menu.appearance = NSAppearance(named: .darkAqua)

        // 创建带样式的菜单项（使用白色字体）
        func createMenuItem(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.menuFont(ofSize: 0)
            ]
            item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
            return item
        }

        // 创建卡片式菜单项
        func createCardMenuItem(title: String, subtitle: String? = nil, icon: String? = nil,
                               action: Selector? = nil, keyEquivalent: String = "") -> NSMenuItem {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: keyEquivalent)
            if action != nil {
                item.keyEquivalentModifierMask = [.command]
            }

            // 创建自定义视图
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: subtitle != nil ? 52 : 36))

            // 图标
            var xOffset: CGFloat = 12
            if let icon = icon {
                let iconSize: CGFloat = 16
                let iconView = NSTextField(labelWithString: icon)
                iconView.font = NSFont.systemFont(ofSize: iconSize)
                iconView.frame = NSRect(x: xOffset, y: (containerView.frame.height - iconSize) / 2,
                                       width: iconSize + 4, height: iconSize)
                iconView.textColor = Design.brandColor
                containerView.addSubview(iconView)
                xOffset += iconSize + 8
            }

            // 标题
            let titleField = NSTextField(frame: NSRect(x: xOffset, y: subtitle != nil ? 24 : 10,
                                                       width: 240 - xOffset, height: 16))
            titleField.stringValue = title
            titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            titleField.textColor = Design.textPrimary
            titleField.lineBreakMode = .byTruncatingTail
            containerView.addSubview(titleField)

            // 副标题
            if let subtitle = subtitle {
                let subtitleField = NSTextField(frame: NSRect(x: xOffset, y: 8,
                                                              width: 240 - xOffset, height: 14))
                subtitleField.stringValue = subtitle
                subtitleField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                subtitleField.textColor = Design.textSecondary
                containerView.addSubview(subtitleField)
            }

            item.view = containerView
            return item
        }

        // 创建统计卡片
        func createStatCard(label: String, value: String, color: NSColor = Design.textPrimary) -> NSMenuItem {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 40))

            // 标签
            let labelField = NSTextField(frame: NSRect(x: 12, y: 20, width: 100, height: 14))
            labelField.stringValue = label
            labelField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            labelField.textColor = Design.textMuted
            containerView.addSubview(labelField)

            // 数值
            let valueField = NSTextField(frame: NSRect(x: 12, y: 4, width: 240, height: 18))
            valueField.stringValue = value
            valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
            valueField.textColor = color
            containerView.addSubview(valueField)

            item.view = containerView
            return item
        }

        // 随机问候语
        let greeting = greetings.randomElement() ?? "ccSwitch 用量统计"
        let greetingItem = createMenuItem(greeting)
        menu.addItem(greetingItem)
        menu.addItem(.separator())

        // 今日统计卡片
        if let stats = DataCache.shared.getCachedToday() {
            // 今日总量（大数字）
            let todayTotal = fmtTitle(stats.total)
            let todayItem = createCardMenuItem(title: "📊 今日用量", subtitle: todayTotal,
                                              icon: "📊", action: #selector(openHourlyDetailToday), keyEquivalent: "t")
            menu.addItem(todayItem)

            // 请求和缓存命中率
            let totalInput = stats.input + stats.cacheCreate + stats.cacheRead
            let cacheRate = totalInput > 0 ? Double(stats.cacheRead) / Double(totalInput) * 100 : 0

            let statsContainer = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))

            // 请求数
            let reqLabel = NSTextField(frame: NSRect(x: 12, y: 18, width: 80, height: 12))
            reqLabel.stringValue = "请求数"
            reqLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            reqLabel.textColor = Design.textMuted
            statsContainer.addSubview(reqLabel)

            let reqValue = NSTextField(frame: NSRect(x: 12, y: 4, width: 80, height: 16))
            reqValue.stringValue = "\(stats.reqs)次"
            reqValue.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            reqValue.textColor = Design.textPrimary
            statsContainer.addSubview(reqValue)

            // 缓存命中率
            let cacheLabel = NSTextField(frame: NSRect(x: 100, y: 18, width: 80, height: 12))
            cacheLabel.stringValue = "缓存命中"
            cacheLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            cacheLabel.textColor = Design.textMuted
            statsContainer.addSubview(cacheLabel)

            let cacheValue = NSTextField(frame: NSRect(x: 100, y: 4, width: 80, height: 16))
            cacheValue.stringValue = String(format: "%.1f%%", cacheRate)
            cacheValue.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            cacheValue.textColor = cacheRate > 80 ? Design.successColor : Design.warningColor
            statsContainer.addSubview(cacheValue)

            // 时长
            if let hours = queryWorkHours() {
                let hoursLabel = NSTextField(frame: NSRect(x: 188, y: 18, width: 80, height: 12))
                hoursLabel.stringValue = "时长"
                hoursLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                hoursLabel.textColor = Design.textMuted
                statsContainer.addSubview(hoursLabel)

                let hoursValue = NSTextField(frame: NSRect(x: 188, y: 4, width: 80, height: 16))
                hoursValue.stringValue = "\(hours)h"
                hoursValue.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                hoursValue.textColor = Design.textPrimary
                statsContainer.addSubview(hoursValue)
            }

            let statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            statsItem.view = statsContainer
            menu.addItem(statsItem)
        } else {
            if FileManager.default.fileExists(atPath: settings.dbPath) {
                let noData = createMenuItem("📊 今日暂无数据")
                menu.addItem(noData)
            } else {
                let noDB = createCardMenuItem(title: "🌶️ 未找到数据源", subtitle: "请去设置",
                                            icon: "🌶️", action: #selector(openSettings))
                menu.addItem(noDB)
            }
        }

        menu.addItem(.separator())

        // 模型分布
        if let models = DataCache.shared.getCachedModelBreakdown(), !models.isEmpty {
            let modelTitle = createCardMenuItem(title: "🤖 模型分布", subtitle: "点击查看详细",
                                              icon: "🤖", action: #selector(openModelDetailToday), keyEquivalent: "b")
            menu.addItem(modelTitle)

            // 显示前3个模型（带进度条样式）
            let maxTotal = models.prefix(3).map { $0.total }.max() ?? 1
            for model in models.prefix(3) {
                let modelName = model.model.count > 18 ? String(model.model.prefix(18)) + "..." : model.model
                let progress = CGFloat(model.total) / CGFloat(maxTotal)

                let modelContainer = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 28))

                // 模型名称
                let nameField = NSTextField(frame: NSRect(x: 24, y: 12, width: 150, height: 14))
                nameField.stringValue = modelName
                nameField.font = NSFont.systemFont(ofSize: 11, weight: .medium)
                nameField.textColor = Design.textPrimary
                modelContainer.addSubview(nameField)

                // 数值
                let valueField = NSTextField(frame: NSRect(x: 175, y: 12, width: 90, height: 14))
                valueField.stringValue = Design.formatTokensK(model.total)
                valueField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                valueField.textColor = Design.textSecondary
                valueField.alignment = .right
                modelContainer.addSubview(valueField)

                // 进度条
                let progressBar = ProgressBarView(frame: NSRect(x: 24, y: 4, width: 240, height: 8))
                progressBar.progress = progress
                progressBar.fillColor = Design.brandColor.withAlphaComponent(0.6)
                modelContainer.addSubview(progressBar)

                let modelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                modelItem.view = modelContainer
                menu.addItem(modelItem)
            }

            menu.addItem(.separator())
        }

        // 昨日统计
        if let stats = DataCache.shared.getCachedYesterday() {
            let yesterdayItem = createCardMenuItem(title: "📅 昨日用量", subtitle: Design.formatTokensK(stats.total),
                                                  icon: "📅", action: #selector(openHourlyDetailYesterday), keyEquivalent: "y")
            menu.addItem(yesterdayItem)
        }

        // 近7天统计
        if let stats = DataCache.shared.getCachedWeek() {
            let weekItem = createCardMenuItem(title: "📊 近7天用量", subtitle: Design.formatTokensK(stats.total),
                                            icon: "📊", action: #selector(openDetail), keyEquivalent: "w")
            menu.addItem(weekItem)
        }

        // 近30天统计
        if let stats = DataCache.shared.getCachedMonth() {
            let monthItem = createCardMenuItem(title: "📆 近30天用量", subtitle: Design.formatTokensK(stats.total),
                                             icon: "📆", action: #selector(openMonthDetail), keyEquivalent: "m")
            menu.addItem(monthItem)
        }

        // 总量
        if let stats = DataCache.shared.getCachedTotal() {
            let totalItem = createCardMenuItem(title: "📊 历史总量", subtitle: Design.formatTokensK(stats.total),
                                             icon: "📊", action: #selector(openMonthDetail), keyEquivalent: "a")
            menu.addItem(totalItem)
        }

        menu.addItem(.separator())

        // 操作按钮
        let copyItem = createCardMenuItem(title: "📋 复制今日统计", icon: "📋",
                                        action: #selector(copyStats), keyEquivalent: "c")
        menu.addItem(copyItem)

        let refreshItem = createCardMenuItem(title: "🔄 刷新数据", icon: "🔄",
                                           action: #selector(refreshData), keyEquivalent: "r")
        menu.addItem(refreshItem)

        let settingsItem = createCardMenuItem(title: "⚙️ 设置", icon: "⚙️",
                                            action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)

        // 退出
        let quitItem = createCardMenuItem(title: "❌ 退出", icon: "❌",
                                        action: #selector(quit), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
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
            statusItem.button?.title = totalStr
        }

        // 更新菜单
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
        if n >= 100_000_000 {
            let d = Double(n) / 100_000_000
            return String(format: "%.4f亿", d)
        } else if n >= 10_000 {
            let w = n / 10_000
            return "\(w)万"
        } else {
            return "\(n)"
        }
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

        // 显示提示
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

    @objc func openDetail() {
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ccBar 设置"
        window.center()

        super.init(window: window)

        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }

        var y: CGFloat = 380

        // 刷新间隔
        let intervalLabel = NSTextField(labelWithString: "刷新间隔 (秒):")
        intervalLabel.frame = NSRect(x: 20, y: y, width: 120, height: 22)
        contentView.addSubview(intervalLabel)

        intervalField = NSTextField(frame: NSRect(x: 150, y: y, width: 80, height: 22))
        contentView.addSubview(intervalField)

        let intervalHint = NSTextField(labelWithString: "范围: 5 - 3000")
        intervalHint.frame = NSRect(x: 240, y: y, width: 200, height: 22)
        intervalHint.textColor = .secondaryLabelColor
        contentView.addSubview(intervalHint)

        y -= 50

        // 数据库路径
        let pathLabel = NSTextField(labelWithString: "数据库路径:")
        pathLabel.frame = NSRect(x: 20, y: y, width: 120, height: 22)
        contentView.addSubview(pathLabel)

        pathField = NSTextField(frame: NSRect(x: 150, y: y, width: 220, height: 22))
        pathField.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(pathField)

        let browseBtn = NSButton(title: "浏览", target: self, action: #selector(browsePath))
        browseBtn.frame = NSRect(x: 380, y: y, width: 60, height: 22)
        contentView.addSubview(browseBtn)

        y -= 25

        // 路径提示
        let pathHint = NSTextField(labelWithString: "默认: ~/.cc-switch/cc-switch.db")
        pathHint.frame = NSRect(x: 150, y: y, width: 300, height: 18)
        pathHint.textColor = .secondaryLabelColor
        pathHint.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(pathHint)

        y -= 25

        // 用量预警阈值
        let warningLabel = NSTextField(labelWithString: "预警阈值 (万):")
        warningLabel.frame = NSRect(x: 20, y: y, width: 120, height: 22)
        contentView.addSubview(warningLabel)

        warningField = NSTextField(frame: NSRect(x: 150, y: y, width: 120, height: 22))
        contentView.addSubview(warningField)

        let warningHint = NSTextField(labelWithString: "超过此值将弹出通知提醒")
        warningHint.frame = NSRect(x: 280, y: y, width: 200, height: 22)
        warningHint.textColor = .secondaryLabelColor
        contentView.addSubview(warningHint)

        y -= 40

        // 启用预警
        warningCheck = NSButton(checkboxWithTitle: "启用用量预警", target: nil, action: nil)
        warningCheck.frame = NSRect(x: 150, y: y, width: 200, height: 22)
        contentView.addSubview(warningCheck)

        y -= 50

        // 开机自启
        launchCheck = NSButton(checkboxWithTitle: "开机自动启动", target: nil, action: nil)
        launchCheck.frame = NSRect(x: 150, y: y, width: 200, height: 22)
        contentView.addSubview(launchCheck)

        y -= 60

        // 保存按钮
        let saveBtn = NSButton(title: "保存", target: self, action: #selector(saveSettings))
        saveBtn.frame = NSRect(x: 150, y: y, width: 80, height: 32)
        saveBtn.bezelStyle = .rounded
        contentView.addSubview(saveBtn)

        // 重置按钮
        let resetBtn = NSButton(title: "重置", target: self, action: #selector(resetSettings))
        resetBtn.frame = NSRect(x: 250, y: y, width: 80, height: 32)
        resetBtn.bezelStyle = .rounded
        contentView.addSubview(resetBtn)
    }

    func loadSettings() {
        intervalField.stringValue = "\(settings.refreshInterval)"

        // 确保显示默认路径
        let path = settings.dbPath
        let displayPath = path.isEmpty ? "\(NSHomeDirectory())/.cc-switch/cc-switch.db" : path
        pathField.stringValue = displayPath
        pathField.toolTip = displayPath  // 添加工具提示，鼠标悬停显示完整路径

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
            }
        }
    }

    @objc func saveSettings() {
        // 保存刷新间隔
        if let interval = Int(intervalField.stringValue), interval >= 5 && interval <= 3000 {
            settings.refreshInterval = interval
        }

        // 保存数据库路径
        settings.dbPath = pathField.stringValue

        // 保存预警设置
        if let threshold = Int(warningField.stringValue), threshold > 0 {
            settings.warningThreshold = threshold
        }
        settings.warningEnabled = warningCheck.state == .on

        // 保存开机自启设置
        settings.launchAtLogin = launchCheck.state == .on
        setLaunchAtLogin(settings.launchAtLogin)

        // 通知保存完成
        let alert = NSAlert()
        alert.messageText = "设置已保存"
        alert.informativeText = "新的设置将在下次刷新时生效"
        alert.runModal()

        onSave()
    }

    @objc func resetSettings() {
        settings.refreshInterval = 30
        settings.dbPath = "\(NSHomeDirectory())/.cc-switch/cc-switch.db"
        settings.warningThreshold = 500000
        settings.warningEnabled = true
        settings.launchAtLogin = false
        loadSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // 使用 Login Items API
        let appPath = Bundle.main.bundlePath
        let loginItems = "/Library/Items"

        if enabled {
            // 创建登录项
            let plist: [String: Any] = [
                "Label": "com.ccbar.launcher",
                "ProgramArguments": [appPath],
                "RunAtLoad": true
            ]

            let plistPath = "\(loginItems)/com.ccbar.launcher.plist"
            let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

            try? FileManager.default.createDirectory(atPath: loginItems, withIntermediateDirectories: true)
            try? plistData?.write(to: URL(fileURLWithPath: plistPath))
        } else {
            // 删除登录项
            let plistPath = "\(loginItems)/com.ccbar.launcher.plist"
            try? FileManager.default.removeItem(atPath: plistPath)
        }
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
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
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
        dateLabel.textColor = NSColor.white
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
            label.textColor = NSColor(white: 0.6, alpha: 1.0)
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

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 7天数据
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0

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
        }

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
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
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
        dateLabel.textColor = NSColor.white
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
            label.textColor = NSColor(white: 0.6, alpha: 1.0)
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

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 本月每天数据
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0

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
        }

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
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
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
        dateLabel.textColor = NSColor.white
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
            label.textColor = NSColor(white: 0.6, alpha: 1.0)
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

        // 标题行
        let headerRow = createHeaderRow()
        contentStack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        contentStack.addArrangedSubview(createSeparator())

        // 计算合计
        var totalReqs = 0
        var totalToken: Int64 = 0
        var totalCacheRead: Int64 = 0
        for model in models {
            totalReqs += model.reqs
            totalToken += model.totalToken
            totalCacheRead += model.cacheRead
        }

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
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1.0)
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
        dateLabel.textColor = NSColor.white
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
            label.textColor = NSColor(white: 0.6, alpha: 1.0)
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
