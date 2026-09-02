import AppKit
import SQLite3

// MARK: - Settings
class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    var refreshInterval: Double {
        get { defaults.double(forKey: "refreshInterval").clamped(5, 3000, fallback: 30) }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }
    var dbPath: String {
        get { defaults.string(forKey: "dbPath") ?? "" }
        set { defaults.set(newValue, forKey: "dbPath") }
    }
    var effectiveDbPath: String {
        let saved = dbPath
        if !saved.isEmpty { return saved }
        return NSHomeDirectory() + "/.cc-switch/cc-switch.db"
    }
}

extension Double {
    func clamped(_ min: Double, _ max: Double, fallback: Double) -> Double {
        self > 0 ? Swift.min(Swift.max(self, min), max) : fallback
    }
}

// MARK: - Settings Window
class SettingsWindowController: NSWindowController {
    let intervalField = NSTextField(frame: .zero)
    let dbPathField = NSTextField(frame: .zero)
    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "⚙️ ccBar 设置"
        window.center()
        self.init(window: window)
        setupUI()
    }

    func setupUI() {
        guard let contentView = window?.contentView else { return }
        let padding: CGFloat = 20

        // Refresh interval
        let intervalLabel = NSTextField(labelWithString: "刷新间隔（秒）：")
        intervalLabel.frame = NSRect(x: padding, y: 120, width: 120, height: 22)
        intervalLabel.isEditable = false; intervalLabel.isBordered = false; intervalLabel.drawsBackground = false
        contentView.addSubview(intervalLabel)

        intervalField.frame = NSRect(x: 150, y: 118, width: 80, height: 26)
        intervalField.stringValue = "\(Int(Settings.shared.refreshInterval))"
        intervalField.placeholderString = "30"
        contentView.addSubview(intervalField)

        let secLabel = NSTextField(labelWithString: "秒（5-3000）")
        secLabel.frame = NSRect(x: 238, y: 120, width: 100, height: 22)
        secLabel.isEditable = false; secLabel.isBordered = false; secLabel.drawsBackground = false
        contentView.addSubview(secLabel)

        // DB path
        let dbLabel = NSTextField(labelWithString: "数据库路径：")
        dbLabel.frame = NSRect(x: padding, y: 80, width: 120, height: 22)
        dbLabel.isEditable = false; dbLabel.isBordered = false; dbLabel.drawsBackground = false
        contentView.addSubview(dbLabel)

        dbPathField.frame = NSRect(x: 150, y: 78, width: 220, height: 26)
        dbPathField.stringValue = Settings.shared.dbPath
        dbPathField.placeholderString = "~/.cc-switch/cc-switch.db（默认）"
        contentView.addSubview(dbPathField)

        let browseBtn = NSButton(frame: NSRect(x: 376, y: 77, width: 30, height: 28))
        browseBtn.title = "📂"
        browseBtn.bezelStyle = .inline
        browseBtn.target = self
        browseBtn.action = #selector(browse)
        contentView.addSubview(browseBtn)

        // Buttons
        let saveBtn = NSButton(frame: NSRect(x: 240, y: 20, width: 80, height: 32))
        saveBtn.title = "保存"
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.target = self
        saveBtn.action = #selector(save)
        contentView.addSubview(saveBtn)

        let cancelBtn = NSButton(frame: NSRect(x: 150, y: 20, width: 80, height: 32))
        cancelBtn.title = "取消"
        cancelBtn.bezelStyle = .rounded
        cancelBtn.target = self
        cancelBtn.action = #selector(cancel)
        contentView.addSubview(cancelBtn)
    }

    @objc func save() {
        if let val = Double(intervalField.stringValue), val >= 5, val <= 3000 {
            Settings.shared.refreshInterval = val
        }
        Settings.shared.dbPath = dbPathField.stringValue.trimmingCharacters(in: .whitespaces)
        window?.close()
        onSave?()
    }

    @objc func cancel() { window?.close() }

    @objc func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "db")!, .init(filenameExtension: "sqlite")!]
        if panel.runModal() == .OK, let url = panel.url {
            dbPathField.stringValue = url.path
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var settingsWC: SettingsWindowController?

    let greetings = [
        "主人今天辛苦啦~", "加油冲鸭！", "摸鱼也要有数据支撑~",
        "今天也要元气满满哦！", "努力写码中...", "Token在燃烧~",
        "效率拉满！", "卷起来了！", "今天心情好~", "代码写得飞起！",
        "干就完了！", "数据就是力量~", "加油鸭！", "冲冲冲！",
        "今天又是充实的一天~", "让Token飞一会儿~", "合理摸鱼~",
        "稳住我们能赢！", "钱要花在刀刃上~", "今天也要好好干！",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        menu.autoenablesItems = false
        startTimer()
        updateData(nil)
    }

    func startTimer() {
        timer?.invalidate()
        let interval = Settings.shared.refreshInterval
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(updateData(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
    }

    @objc func updateData(_ sender: Any?) {
        let path = Settings.shared.effectiveDbPath
        var dbPtr: OpaquePointer?
        guard sqlite3_open_v2(path, &dbPtr, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = dbPtr else {
            statusItem.button?.title = "❌"
            menu.removeAllItems()
            let warn = NSMenuItem(title: "🌶️ 未找到数据源，请去设置", action: #selector(openSettings(_:)), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
            let settingsItem = NSMenuItem(title: "⚙️ 设置", action: #selector(openSettings(_:)), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)
            let quitItem = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            statusItem.menu = menu
            return
        }
        defer { sqlite3_close(dbPtr) }

        let today = todayStr()
        let (todayTokens, todayReqs, _) = queryDayStats(db: db, date: today)
        let (models, _) = queryModelBreakdown(db: db, date: today)

        if todayTokens > 0 {
            statusItem.button?.title = fmtK(todayTokens)
        } else {
            let yesterday = dateStr(offset: -1)
            let (yTokens, _, _) = queryDayStats(db: db, date: yesterday)
            statusItem.button?.title = "\(fmtK(yTokens))(昨)"
        }

        menu.removeAllItems()

        let workHours = queryWorkHours(db: db, date: today)
        let header = NSMenuItem(title: "✨ \(greetings.randomElement()!) · \(workHours)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(statItem("🚀 今日请求", "\(todayReqs) 次"))
        menu.addItem(statItem("💎 今日 Token", fmtK(todayTokens)))
        menu.addItem(.separator())

        let modelHeader = NSMenuItem(title: "🤖 模型明细", action: nil, keyEquivalent: "")
        modelHeader.isEnabled = false
        menu.addItem(modelHeader)
        for m in models.prefix(8) {
            menu.addItem(statItem("  \(m.name)", "\(fmtK(m.tokens)) · \(m.reqs)次"))
        }
        menu.addItem(.separator())

        let (weekTokens, weekReqs, _) = queryRangeStats(db: db, days: 7)
        menu.addItem(statItem("📅 近7天 Token", "\(fmtK(weekTokens)) · \(weekReqs)次"))
        let (monthTokens, monthReqs, _) = queryRangeStats(db: db, days: 30)
        menu.addItem(statItem("📅 近30天 Token", "\(fmtK(monthTokens)) · \(monthReqs)次"))
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "🔄 刷新", action: #selector(updateData(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "⚙️ 设置", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func openSettings(_ sender: Any?) {
        settingsWC = SettingsWindowController()
        settingsWC?.onSave = { [weak self] in
            self?.startTimer()
            self?.updateData(nil)
        }
        settingsWC?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func queryWorkHours(db: OpaquePointer, date: String) -> String {
        let sql = "SELECT MIN(created_at) FROM proxy_request_logs WHERE date(created_at, 'unixepoch', 'localtime') = ?"
        var stmt: OpaquePointer?
        var hours = ""
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                let firstTs = sqlite3_column_int64(stmt, 0)
                let now = Int64(Date().timeIntervalSince1970)
                let elapsed = Double(now - firstTs) / 3600.0
                if elapsed > 0 { hours = String(format: "%.1fh", elapsed) }
            }
        }
        sqlite3_finalize(stmt)
        return hours.isEmpty ? "刚开工" : hours
    }

    func statItem(_ label: String, _ value: String) -> NSMenuItem {
        let item = NSMenuItem(title: "\(label)    \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func queryDayStats(db: OpaquePointer, date: String) -> (Int, Int, Double) {
        let sql = """
            SELECT COALESCE(SUM(input_tokens + output_tokens + cache_read_tokens), 0),
                   COALESCE(SUM(request_count), 0),
                   COALESCE(SUM(CAST(total_cost_usd AS REAL)), 0)
            FROM (
                SELECT input_tokens, output_tokens, cache_read_tokens, 1 as request_count, total_cost_usd
                FROM proxy_request_logs WHERE date(created_at, 'unixepoch', 'localtime') = ?
                UNION ALL
                SELECT input_tokens, output_tokens, cache_read_tokens, request_count, total_cost_usd
                FROM usage_daily_rollups WHERE date = ?
            )
        """
        var stmt: OpaquePointer?
        var tokens = 0, reqs = 0; var cost = 0.0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                tokens = Int(sqlite3_column_int(stmt, 0))
                reqs = Int(sqlite3_column_int(stmt, 1))
                cost = sqlite3_column_double(stmt, 2)
            }
        }
        sqlite3_finalize(stmt)
        return (tokens, reqs, cost)
    }

    func queryRangeStats(db: OpaquePointer, days: Int) -> (Int, Int, Double) {
        let startDate = dateStr(offset: -days)
        let sql = """
            SELECT COALESCE(SUM(input_tokens + output_tokens + cache_read_tokens), 0),
                   COALESCE(SUM(cnt), 0),
                   COALESCE(SUM(cost), 0)
            FROM (
                SELECT input_tokens, output_tokens, cache_read_tokens, 1 as cnt, CAST(total_cost_usd AS REAL) as cost
                FROM proxy_request_logs WHERE date(created_at, 'unixepoch', 'localtime') >= ?
                UNION ALL
                SELECT input_tokens, output_tokens, cache_read_tokens, request_count as cnt, CAST(total_cost_usd AS REAL) as cost
                FROM usage_daily_rollups WHERE date >= ?
            )
        """
        var stmt: OpaquePointer?
        var tokens = 0, reqs = 0; var cost = 0.0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, startDate, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, startDate, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                tokens = Int(sqlite3_column_int(stmt, 0))
                reqs = Int(sqlite3_column_int(stmt, 1))
                cost = sqlite3_column_double(stmt, 2)
            }
        }
        sqlite3_finalize(stmt)
        return (tokens, reqs, cost)
    }

    struct ModelStat { let name: String; let tokens: Int; let reqs: Int }

    func queryModelBreakdown(db: OpaquePointer, date: String) -> ([ModelStat], Int) {
        let sql = """
            SELECT model, SUM(input_tokens + output_tokens + cache_read_tokens) as total,
                   SUM(reqs) as reqs FROM (
                SELECT model, input_tokens, output_tokens, cache_read_tokens, 1 as reqs
                FROM proxy_request_logs WHERE date(created_at, 'unixepoch', 'localtime') = ?
                UNION ALL
                SELECT model, input_tokens, output_tokens, cache_read_tokens, request_count as reqs
                FROM usage_daily_rollups WHERE date = ?
            ) GROUP BY model ORDER BY total DESC
        """
        var stmt: OpaquePointer?
        var models: [ModelStat] = []
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, date, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let name = String(cString: sqlite3_column_text(stmt, 0))
                let tokens = Int(sqlite3_column_int(stmt, 1))
                let reqs = Int(sqlite3_column_int(stmt, 2))
                models.append(ModelStat(name: name, tokens: tokens, reqs: reqs))
            }
        }
        sqlite3_finalize(stmt)
        return (models, models.reduce(0) { $0 + $1.tokens })
    }

    func todayStr() -> String { dateStr(offset: 0) }

    func dateStr(offset: Int) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }

    func fmtK(_ v: Int) -> String {
        if v >= 100_000_000 { return String(format: "%.4f亿", Double(v) / 1e8) }
        if v >= 10_000 { return "\(v / 10000)万" }
        return "\(v)"
    }

    @objc func quit(_ sender: Any?) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
