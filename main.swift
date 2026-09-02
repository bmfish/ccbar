import Cocoa
import SQLite3

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
        get { defaults.integer(forKey: "warningThreshold") == 0 ? 500000 : defaults.integer(forKey: "warningThreshold") }
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
    private var modelBreakdown: [(model: String, input: Int64, output: Int64, total: Int64)]?
    private var lastUpdate: Date = Date.distantPast

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

    func getCachedModelBreakdown() -> [(model: String, input: Int64, output: Int64, total: Int64)]? {
        return modelBreakdown
    }

    func update(
        today: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        yesterday: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        week: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        month: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)?,
        models: [(model: String, input: Int64, output: Int64, total: Int64)]?
    ) {
        self.todayStats = today
        self.yesterdayStats = yesterday
        self.weekStats = week
        self.monthStats = month
        self.modelBreakdown = models
        self.lastUpdate = Date()
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
    var lastNotificationDate: Date?

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

        // 初始图标
        updateIcon()

        // 初始数据库连接
        connectDB()

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

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: TimeInterval(settings.refreshInterval),
                                     target: self,
                                     selector: #selector(updateData),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc func updateData() {
        // 查询今日统计
        let todayStats = queryDayStats(days: 0)

        // 查询昨日统计（用于对比）
        let yesterdayStats = queryDayStats(days: 1)

        // 查询近7天统计
        let weekStats = queryDayStats(days: 7)

        // 查询近30天统计
        let monthStats = queryDayStats(days: 30)

        // 查询模型分布
        let modelBreakdown = queryModelBreakdown()

        // 更新缓存
        DataCache.shared.update(
            today: todayStats,
            yesterday: yesterdayStats,
            week: weekStats,
            month: monthStats,
            models: modelBreakdown
        )

        // 更新标题
        if let stats = todayStats {
            let totalStr = fmtK(stats.total)
            statusItem.button?.title = totalStr

            // 检查预警
            checkWarning(stats: stats)
        } else {
            statusItem.button?.title = "未找到"
        }

        // 更新菜单
        updateMenu()
    }

    func queryDayStats(days: Int) -> (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)? {
        guard let db = db else { return nil }

        var stmt: OpaquePointer?
        let sql: String

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
            WHERE datetime(created_at, 'unixepoch', 'localtime') >= date('now')
            """
        } else if days == 1 {
            // 昨日
            sql = """
            SELECT
                COUNT(*) as reqs,
                COALESCE(SUM(input_tokens), 0) as input,
                COALESCE(SUM(output_tokens), 0) as output,
                COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
                COALESCE(SUM(cache_read_tokens), 0) as cache_read
            FROM proxy_request_logs
            WHERE datetime(created_at, 'unixepoch', 'localtime') >= date('now', '-1 day')
            AND datetime(created_at, 'unixepoch', 'localtime') < date('now')
            """
        } else {
            // 近N天
            sql = """
            SELECT
                COUNT(*) as reqs,
                COALESCE(SUM(input_tokens), 0) as input,
                COALESCE(SUM(output_tokens), 0) as output,
                COALESCE(SUM(cache_creation_tokens), 0) as cache_create,
                COALESCE(SUM(cache_read_tokens), 0) as cache_read
            FROM proxy_request_logs
            WHERE datetime(created_at, 'unixepoch', 'localtime') >= date('now', '-\(days) days')
            """
        }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
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

        var stmt: OpaquePointer?
        let sql = """
        SELECT
            model,
            COALESCE(SUM(input_tokens), 0) as input,
            COALESCE(SUM(output_tokens), 0) as output,
            COALESCE(SUM(input_tokens + output_tokens), 0) as total
        FROM proxy_request_logs
        WHERE datetime(created_at, 'unixepoch', 'localtime') >= date('now')
        GROUP BY model
        ORDER BY total DESC
        LIMIT 5
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

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

        var stmt: OpaquePointer?
        let sql = """
        SELECT MIN(created_at)
        FROM proxy_request_logs
        WHERE datetime(created_at, 'unixepoch', 'localtime') >= date('now')
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }

        var result: String?

        if sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = sqlite3_column_int64(stmt, 0)
            if timestamp > 0 {
                let startDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let hours = Date().timeIntervalSince(startDate) / 3600
                if hours > 0 && hours < 24 {
                    result = String(format: "%.1f", hours)
                }
            }
        }

        sqlite3_finalize(stmt)
        return result
    }

    func checkWarning(stats: (reqs: Int, input: Int64, output: Int64, cacheCreate: Int64, cacheRead: Int64, total: Int64)) {
        guard settings.warningEnabled else { return }

        // 检查是否超过阈值
        if stats.total >= Int64(settings.warningThreshold) {
            // 检查是否已经通知过（避免重复通知）
            let now = Date()
            if let lastDate = lastNotificationDate,
               now.timeIntervalSince(lastDate) < 3600 {
                return // 1小时内不重复通知
            }

            // 发送通知
            sendNotification(total: stats.total)
            lastNotificationDate = now
        }
    }

    func sendNotification(total: Int64) {
        let notification = NSUserNotification()
        notification.title = "⚠️ 用量预警"
        notification.informativeText = "今日 Token 用量已达 \(fmtK(total))，超过预警阈值 \(fmtK(Int64(settings.warningThreshold)))"
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

        // 随机问候语
        let greeting = greetings.randomElement() ?? "ccSwitch 用量统计"
        let greetingItem = NSMenuItem(title: greeting, action: nil, keyEquivalent: "")
        greetingItem.isEnabled = false
        menu.addItem(greetingItem)
        menu.addItem(.separator())

        // 今日统计
        if let stats = DataCache.shared.getCachedToday() {
            let todayTotal = NSMenuItem(title: "📊 今日 Token: \(fmtK(stats.total))", action: nil, keyEquivalent: "")
            todayTotal.isEnabled = false
            menu.addItem(todayTotal)

            // 对比昨日
            if let yesterday = DataCache.shared.getCachedYesterday(), yesterday.total > 0 {
                let change = Double(stats.total - yesterday.total) / Double(yesterday.total) * 100
                let emoji = change >= 0 ? "📈" : "📉"
                let changeStr = String(format: "%+.1f%%", change)
                let compareItem = NSMenuItem(title: "  \(emoji) 较昨日 \(changeStr)", action: nil, keyEquivalent: "")
                compareItem.isEnabled = false
                menu.addItem(compareItem)
            }

            let todayReqs = NSMenuItem(title: "  🔢 请求: \(stats.reqs)次", action: nil, keyEquivalent: "")
            todayReqs.isEnabled = false
            menu.addItem(todayReqs)

            let todayInput = NSMenuItem(title: "  📥 输入: \(fmtK(stats.input))", action: nil, keyEquivalent: "")
            todayInput.isEnabled = false
            menu.addItem(todayInput)

            let todayOutput = NSMenuItem(title: "  📤 输出: \(fmtK(stats.output))", action: nil, keyEquivalent: "")
            todayOutput.isEnabled = false
            menu.addItem(todayOutput)

            // 工作时长
            if let hours = queryWorkHours() {
                let hoursItem = NSMenuItem(title: "  ⏱️ 工作时长: \(hours)小时", action: nil, keyEquivalent: "")
                hoursItem.isEnabled = false
                menu.addItem(hoursItem)
            }
        } else {
            if FileManager.default.fileExists(atPath: settings.dbPath) {
                let noData = NSMenuItem(title: "📊 今日暂无数据", action: nil, keyEquivalent: "")
                noData.isEnabled = false
                menu.addItem(noData)
            } else {
                let noDB = NSMenuItem(title: "🌶️ 未找到数据源，请去设置", action: #selector(openSettings), keyEquivalent: "")
                menu.addItem(noDB)
            }
        }

        menu.addItem(.separator())

        // 模型分布
        if let models = DataCache.shared.getCachedModelBreakdown(), !models.isEmpty {
            let modelTitle = NSMenuItem(title: "🤖 模型分布", action: nil, keyEquivalent: "")
            modelTitle.isEnabled = false
            menu.addItem(modelTitle)

            for model in models.prefix(3) {
                let modelName = model.model.count > 20 ? String(model.model.prefix(20)) + "..." : model.model
                let modelItem = NSMenuItem(title: "  \(modelName): \(fmtK(model.total))", action: nil, keyEquivalent: "")
                modelItem.isEnabled = false
                menu.addItem(modelItem)
            }

            menu.addItem(.separator())
        }

        // 近7天统计
        if let stats = DataCache.shared.getCachedWeek() {
            let weekItem = NSMenuItem(title: "📅 近7天 Token: \(fmtK(stats.total))", action: nil, keyEquivalent: "")
            weekItem.isEnabled = false
            menu.addItem(weekItem)
        }

        // 近30天统计
        if let stats = DataCache.shared.getCachedMonth() {
            let monthItem = NSMenuItem(title: "📆 近30天 Token: \(fmtK(stats.total))", action: nil, keyEquivalent: "")
            monthItem.isEnabled = false
            menu.addItem(monthItem)
        }

        menu.addItem(.separator())

        // 复制统计
        let copyItem = NSMenuItem(title: "📋 复制今日统计", action: #selector(copyStats), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command]
        menu.addItem(copyItem)

        // 设置
        let settingsItem = NSMenuItem(title: "⚙️ 设置", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        // 退出
        let quitItem = NSMenuItem(title: "❌ 退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func fmtK(_ n: Int64) -> String {
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
        let warningLabel = NSTextField(labelWithString: "预警阈值 (Token):")
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

// 主程序
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
