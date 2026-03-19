import Cocoa
import AVFoundation

// MARK: - Constants

private enum Settings {
    static let topic = "UNLOCK_NTFY_TOPIC"
    static let alertTitle = "UNLOCK_ALERT_TITLE"
    static let alertMessage = "UNLOCK_ALERT_MESSAGE"
    static let passwordHash = "UNLOCK_PASSWORD_HASH"
    static let schedules = "UNLOCK_SCHEDULES"

    static let defaultTitle = "⚠️ 무단 접근 감지"
    static let defaultMessage = "[{hostname}] {timestamp}에 Mac 잠금이 해제되었습니다.\n본인이 아닌 경우 즉시 확인하세요."
}

// MARK: - Schedule

struct Schedule: Codable {
    var name: String        // "평일 야간", "주말 종일"
    var days: [Int]         // 1=일, 2=월, 3=화, 4=수, 5=목, 6=금, 7=토
    var startHour: Int      // 0~23
    var endHour: Int        // 0~24 (24 = 자정)
    var allDay: Bool

    static let dayNames = ["일", "월", "화", "수", "목", "금", "토"]

    func matches(now: Date) -> Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=일, 2=월, ..., 7=토
        guard days.contains(weekday) else { return false }
        if allDay { return true }
        let hour = cal.component(.hour, from: now)
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // 야간 (예: 23~07)
            return hour >= startHour || hour < endHour
        }
    }

    var summary: String {
        let dayStr = days.sorted().map { Schedule.dayNames[$0 - 1] }.joined(separator: ",")
        let timeStr = allDay ? "종일" : String(format: "%02d:00-%02d:00", startHour, endHour)
        return "\(dayStr) \(timeStr)"
    }

    static func load() -> [Schedule] {
        guard let data = UserDefaults.standard.data(forKey: Settings.schedules),
              let list = try? JSONDecoder().decode([Schedule].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Schedule]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Settings.schedules)
        }
    }

    static func shouldNotify(schedules: [Schedule], now: Date = Date()) -> Bool {
        if schedules.isEmpty { return true }
        return schedules.contains { $0.matches(now: now) }
    }
}

// MARK: - Password

import CryptoKit

private enum PasswordManager {
    static var isSet: Bool {
        UserDefaults.standard.string(forKey: Settings.passwordHash) != nil
    }

    static func hash(_ password: String) -> String {
        let data = Data(password.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ password: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: Settings.passwordHash) else { return false }
        return hash(password) == stored
    }

    static func save(_ password: String) {
        UserDefaults.standard.set(hash(password), forKey: Settings.passwordHash)
    }

    static func promptVerify() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "비밀번호 입력"
        alert.informativeText = "설정 변경을 위해 비밀번호를 입력하세요."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "비밀번호"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let pw = input.stringValue
        if verify(pw) { return true }

        let fail = NSAlert()
        fail.messageText = "비밀번호가 틀렸습니다."
        fail.alertStyle = .warning
        fail.runModal()
        return false
    }

    static func promptSetup() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "비밀번호 설정"
        alert.informativeText = "설정 보호를 위한 비밀번호를 입력하세요."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
        let pw = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        pw.placeholderString = "비밀번호"
        container.addSubview(pw)
        let confirm = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        confirm.placeholderString = "비밀번호 확인"
        container.addSubview(confirm)

        alert.accessoryView = container
        alert.window.initialFirstResponder = pw

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let p = pw.stringValue
        guard !p.isEmpty, p == confirm.stringValue else {
            let fail = NSAlert()
            fail.messageText = "비밀번호가 일치하지 않거나 비어있습니다."
            fail.alertStyle = .warning
            fail.runModal()
            return
        }
        save(p)
    }

    /// Returns true if authenticated (password not set, or verified)
    static func requireAuth() -> Bool {
        guard isSet else { return true }
        return promptVerify()
    }
}

private enum LaunchAgent {
    static let label = "com.user.unlock-notifier"
    static var plistPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/LaunchAgents/\(label).plist"
    }

    static func install() {
        guard !FileManager.default.fileExists(atPath: plistPath),
              let execPath = Bundle.main.executablePath else { return }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key>
          <array><string>\(execPath)</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>/tmp/unlock-notifier.out.log</string>
          <key>StandardErrorPath</key><string>/tmp/unlock-notifier.err.log</string>
        </dict>
        </plist>
        """

        guard let _ = try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8) else {
            fputs("WARNING: Failed to write LaunchAgent plist\n", stderr)
            return
        }
        launchctl(["load", plistPath])
        fputs("LaunchAgent installed\n", stderr)
    }

    static func uninstall() {
        launchctl(["unload", plistPath])
        try? FileManager.default.removeItem(atPath: plistPath)
    }

    private static func launchctl(_ args: [String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        try? proc.run()
        proc.waitUntilExit()
    }
}

// MARK: - Camera

class CameraCapture: NSObject, AVCapturePhotoCaptureDelegate {
    private var session: AVCaptureSession?
    private var outputPath: String?
    private var onComplete: ((String?) -> Void)?

    func take(to path: String, done: @escaping (String?) -> Void) {
        outputPath = path
        onComplete = done

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            fputs("WARNING: Camera not available\n", stderr)
            done(nil)
            return
        }

        let output = AVCapturePhotoOutput()
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        session.startRunning()

        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { session?.stopRunning(); session = nil }

        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let path = outputPath else {
            fputs("WARNING: Capture failed: \(error?.localizedDescription ?? "unknown")\n", stderr)
            onComplete?(nil)
            return
        }

        do {
            try data.write(to: URL(fileURLWithPath: path))
            onComplete?(path)
        } catch {
            fputs("WARNING: Save failed: \(error.localizedDescription)\n", stderr)
            onComplete?(nil)
        }
    }
}

// MARK: - Ntfy Client

struct NtfyClient {
    let topic: String

    var webURL: String { "https://ntfy.sh/\(topic)" }

    func send(photoPath: String?, title: String, message: String) {
        let hostname = Host.current().localizedName ?? "Mac"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = df.string(from: Date())

        let resolvedMessage = message
            .replacingOccurrences(of: "{hostname}", with: hostname)
            .replacingOccurrences(of: "{timestamp}", with: timestamp)

        let attachURL = uploadPhoto(path: photoPath)

        var json: [String: Any] = [
            "topic": topic,
            "title": title,
            "message": resolvedMessage,
            "priority": 4,
            "tags": ["warning"],
            "click": webURL
        ]
        if let url = attachURL { json["attach"] = url }

        var request = URLRequest(url: URL(string: "https://ntfy.sh")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)

        syncRequest(request)
    }

    private func uploadPhoto(path: String?) -> String? {
        guard let path = path,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { return nil }

        var request = URLRequest(url: URL(string: "https://ntfy.sh/\(topic)-upload")!)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("unlock-photo.jpg", forHTTPHeaderField: "Filename")

        var attachURL: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let attachment = json["attachment"] as? [String: Any],
               let url = attachment["url"] as? String {
                attachURL = url
            }
            sem.signal()
        }.resume()
        sem.wait()
        return attachURL
    }

    private func syncRequest(_ request: URLRequest) {
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error { fputs("ERROR: ntfy failed: \(error.localizedDescription)\n", stderr) }
            sem.signal()
        }.resume()
        sem.wait()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var lastEventMenuItem: NSMenuItem!
    private var cameraMenuItem: NSMenuItem!
    private var topicMenuItem: NSMenuItem!
    private var webMenuItem: NSMenuItem!
    private var scheduleMenuItem: NSMenuItem!
    private let camera = CameraCapture()

    var topic = ""
    var alertTitle = Settings.defaultTitle
    var alertMessage = Settings.defaultMessage
    var schedules: [Schedule] = []

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        LaunchAgent.install()
        setupEditMenu()
        setupMenuBar()
        requestCameraIfNeeded()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleUnlock()
        }

        updateStatus()

        if !PasswordManager.isSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PasswordManager.promptSetup()
                self.updateStatus()
            }
        }

        fputs("unlock-notifier started\n", stderr)
    }

    private func loadSettings() {
        topic = UserDefaults.standard.string(forKey: Settings.topic)
            ?? ProcessInfo.processInfo.environment[Settings.topic]
            ?? ""
        if !topic.isEmpty { UserDefaults.standard.set(topic, forKey: Settings.topic) }
        if let t = UserDefaults.standard.string(forKey: Settings.alertTitle) { alertTitle = t }
        if let m = UserDefaults.standard.string(forKey: Settings.alertMessage) { alertMessage = m }
        schedules = Schedule.load()
    }

    // MARK: Menu Setup

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()

        statusMenuItem = menu.addDisabledItem("")
        lastEventMenuItem = menu.addDisabledItem("Last: —")
        menu.addItem(NSMenuItem.separator())

        cameraMenuItem = menu.addActionItem("", target: self, action: #selector(handleCameraAction))
        topicMenuItem = menu.addActionItem("", target: self, action: #selector(handleTopicAction))
        menu.addActionItem("✏️ Edit Message", target: self, action: #selector(handleMessageAction))
        scheduleMenuItem = menu.addActionItem("", target: self, action: #selector(handleScheduleAction))
        menu.addItem(NSMenuItem.separator())

        menu.addActionItem("🧪 Test (force)", target: self, action: #selector(testForce), key: "t")
        menu.addActionItem("🧪 Test (with schedule)", target: self, action: #selector(testWithSchedule))
        webMenuItem = menu.addActionItem("Open Web Dashboard", target: self, action: #selector(openWeb))
        menu.addItem(NSMenuItem.separator())

        menu.addActionItem("🔑 Password", target: self, action: #selector(handlePassword))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(handleQuit), keyEquivalent: "q"))
        menu.addActionItem("Uninstall...", target: self, action: #selector(handleUninstall))

        statusItem.menu = menu
    }

    // MARK: Status

    private func requestCameraIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { self.updateStatus() }
        }
    }

    private func updateStatus() {
        let passwordSet = PasswordManager.isSet
        let cameraOk = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let topicOk = !topic.isEmpty
        let ready = passwordSet && cameraOk && topicOk

        setIcon(ready ? "lock.shield" : "lock.trianglebadge.exclamationmark")

        if !passwordSet {
            statusMenuItem.title = "🔑 비밀번호를 먼저 설정하세요"
        } else if ready {
            statusMenuItem.title = "✅ Monitoring"
        } else {
            statusMenuItem.title = "⚠️ Setup required"
        }

        cameraMenuItem.title = cameraOk ? "📷 Camera: Granted" : "📷 Camera: ⚠️ Click to allow"
        cameraMenuItem.isEnabled = passwordSet
        topicMenuItem.title = topicOk ? "🔔 Topic: ••••••" : "🔔 Topic: ⚠️ Click to set"
        topicMenuItem.isEnabled = passwordSet
        webMenuItem.isEnabled = passwordSet && topicOk

        if schedules.isEmpty {
            scheduleMenuItem.title = "⏰ Schedule: Always"
        } else {
            scheduleMenuItem.title = "⏰ Schedule: \(schedules.count) rule\(schedules.count > 1 ? "s" : "")"
        }
        scheduleMenuItem.isEnabled = passwordSet
    }

    private func setIcon(_ name: String) {
        let icon = NSImage(systemSymbolName: name, accessibilityDescription: "Unlock Notifier")
        icon?.isTemplate = true
        statusItem.button?.image = icon
    }

    // MARK: Actions

    @objc private func handleCameraAction() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { self.updateStatus() }
            }
        } else {
            openCameraSettings()
        }
    }

    private func openCameraSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ]
        for urlStr in urls {
            if let url = URL(string: urlStr), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc private func handleTopicAction() {
        guard PasswordManager.requireAuth() else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "ntfy Topic"
        alert.informativeText = "Enter topic ID (iPhone ntfy app에서 동일한 topic을 구독하세요)"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = topic
        input.placeholderString = "e.g. 8962ec85-8438-426f-ace1-c79dc690c61d"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        topic = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if topic.isEmpty {
            UserDefaults.standard.removeObject(forKey: Settings.topic)
        } else {
            UserDefaults.standard.set(topic, forKey: Settings.topic)
        }
        updateStatus()
    }

    @objc private func handleMessageAction() {
        guard PasswordManager.requireAuth() else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "알림 메시지 설정"
        alert.informativeText = "사용 가능한 변수: {hostname}, {timestamp}"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 90))

        let titleLabel = NSTextField(labelWithString: "제목:")
        titleLabel.frame = NSRect(x: 0, y: 65, width: 40, height: 20)
        container.addSubview(titleLabel)

        let titleInput = NSTextField(frame: NSRect(x: 45, y: 62, width: 355, height: 24))
        titleInput.stringValue = alertTitle
        container.addSubview(titleInput)

        let msgLabel = NSTextField(labelWithString: "내용:")
        msgLabel.frame = NSRect(x: 0, y: 5, width: 40, height: 20)
        container.addSubview(msgLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 45, y: 0, width: 355, height: 55))
        let msgInput = NSTextView(frame: scrollView.bounds)
        msgInput.string = alertMessage
        msgInput.font = NSFont.systemFont(ofSize: 13)
        msgInput.isEditable = true
        msgInput.isRichText = false
        scrollView.documentView = msgInput
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)

        alert.accessoryView = container
        alert.window.initialFirstResponder = titleInput

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        alertTitle = titleInput.stringValue
        alertMessage = msgInput.string
        UserDefaults.standard.set(alertTitle, forKey: Settings.alertTitle)
        UserDefaults.standard.set(alertMessage, forKey: Settings.alertMessage)
    }

    @objc private func handleScheduleAction() {
        guard PasswordManager.requireAuth() else { return }
        showScheduleManager()
    }

    private func showScheduleManager() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "알림 스케줄 관리"
        alert.informativeText = "스케줄이 없으면 항상 알림을 보냅니다. 항목을 선택 후 삭제/수정할 수 있습니다."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Delete")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("schedule"))
        col.width = 360
        tableView.addTableColumn(col)

        class ScheduleDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
            var items: [String]
            init(_ items: [String]) { self.items = items }
            func numberOfRows(in tableView: NSTableView) -> Int { max(items.count, 1) }
            func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
                let text = NSTextField(labelWithString: items.isEmpty ? "등록된 스케줄 없음 (Always)" : items[row])
                text.font = NSFont.systemFont(ofSize: 13)
                return text
            }
        }

        let items = schedules.enumerated().map { "\($0 + 1). \($1.name): \($1.summary)" }
        let ds = ScheduleDataSource(items)
        tableView.dataSource = ds
        tableView.delegate = ds
        objc_setAssociatedObject(alert, "ds", ds, .OBJC_ASSOCIATION_RETAIN)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        container.addSubview(scrollView)
        alert.accessoryView = container

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            addScheduleRule()
        } else if response == .alertThirdButtonReturn {
            let selected = tableView.selectedRow
            if selected >= 0 && selected < schedules.count {
                schedules.remove(at: selected)
                Schedule.save(schedules)
                updateStatus()
            }
            showScheduleManager()
        }
    }

    private func addScheduleRule() {
        let alert = NSAlert()
        alert.messageText = "스케줄 추가"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 130))

        // Name
        let nameLabel = NSTextField(labelWithString: "이름:")
        nameLabel.frame = NSRect(x: 0, y: 105, width: 40, height: 20)
        container.addSubview(nameLabel)
        let nameInput = NSTextField(frame: NSRect(x: 45, y: 102, width: 335, height: 24))
        nameInput.placeholderString = "예: 평일 야간"
        container.addSubview(nameInput)

        // Days
        let dayLabel = NSTextField(labelWithString: "요일:")
        dayLabel.frame = NSRect(x: 0, y: 75, width: 40, height: 20)
        container.addSubview(dayLabel)

        var dayChecks: [NSButton] = []
        for (i, name) in Schedule.dayNames.enumerated() {
            let btn = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            btn.frame = NSRect(x: 45 + i * 48, y: 73, width: 46, height: 20)
            container.addSubview(btn)
            dayChecks.append(btn)
        }

        // All day
        let allDayCheck = NSButton(checkboxWithTitle: "종일", target: nil, action: nil)
        allDayCheck.frame = NSRect(x: 45, y: 45, width: 60, height: 20)
        container.addSubview(allDayCheck)

        // Time
        let startLabel = NSTextField(labelWithString: "시간:")
        startLabel.frame = NSRect(x: 120, y: 45, width: 40, height: 20)
        container.addSubview(startLabel)

        let startPicker = NSTextField(frame: NSRect(x: 160, y: 43, width: 45, height: 24))
        startPicker.stringValue = "23"
        startPicker.alignment = .center
        container.addSubview(startPicker)

        let dash = NSTextField(labelWithString: "~")
        dash.frame = NSRect(x: 208, y: 45, width: 15, height: 20)
        container.addSubview(dash)

        let endPicker = NSTextField(frame: NSRect(x: 225, y: 43, width: 45, height: 24))
        endPicker.stringValue = "07"
        endPicker.alignment = .center
        container.addSubview(endPicker)

        let hourLabel = NSTextField(labelWithString: "시")
        hourLabel.frame = NSRect(x: 273, y: 45, width: 20, height: 20)
        container.addSubview(hourLabel)

        // Presets
        let presetLabel = NSTextField(labelWithString: "프리셋:")
        presetLabel.frame = NSRect(x: 0, y: 10, width: 50, height: 20)
        container.addSubview(presetLabel)

        let weekdayBtn = NSButton(title: "평일", target: nil, action: nil)
        weekdayBtn.frame = NSRect(x: 55, y: 8, width: 55, height: 24)
        weekdayBtn.bezelStyle = .rounded
        weekdayBtn.target = nil
        weekdayBtn.tag = 1
        container.addSubview(weekdayBtn)

        let weekendBtn = NSButton(title: "주말", target: nil, action: nil)
        weekendBtn.frame = NSRect(x: 115, y: 8, width: 55, height: 24)
        weekendBtn.bezelStyle = .rounded
        weekendBtn.tag = 2
        container.addSubview(weekendBtn)

        let everydayBtn = NSButton(title: "매일", target: nil, action: nil)
        everydayBtn.frame = NSRect(x: 175, y: 8, width: 55, height: 24)
        everydayBtn.bezelStyle = .rounded
        everydayBtn.tag = 3
        container.addSubview(everydayBtn)

        // Preset actions via target-action
        class PresetHelper: NSObject {
            let dayChecks: [NSButton]
            let allDayCheck: NSButton
            init(_ checks: [NSButton], _ allDay: NSButton) { dayChecks = checks; allDayCheck = allDay }
            @objc func weekday(_ sender: Any) { set([2,3,4,5,6]) }
            @objc func weekend(_ sender: Any) { set([1,7]); allDayCheck.state = .on }
            @objc func everyday(_ sender: Any) { set([1,2,3,4,5,6,7]) }
            func set(_ days: [Int]) {
                for (i, btn) in dayChecks.enumerated() {
                    btn.state = days.contains(i + 1) ? .on : .off
                }
            }
        }
        let helper = PresetHelper(dayChecks, allDayCheck)
        weekdayBtn.target = helper; weekdayBtn.action = #selector(PresetHelper.weekday(_:))
        weekendBtn.target = helper; weekendBtn.action = #selector(PresetHelper.weekend(_:))
        everydayBtn.target = helper; everydayBtn.action = #selector(PresetHelper.everyday(_:))
        // Prevent dealloc
        objc_setAssociatedObject(alert, "helper", helper, .OBJC_ASSOCIATION_RETAIN)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameInput

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selectedDays = dayChecks.enumerated().compactMap { $1.state == .on ? $0 + 1 : nil }
        guard !selectedDays.isEmpty else { return }

        let name = nameInput.stringValue.isEmpty ? "Rule \(schedules.count + 1)" : nameInput.stringValue
        let allDay = allDayCheck.state == .on
        let start = Int(startPicker.stringValue) ?? 23
        let end = Int(endPicker.stringValue) ?? 7

        let rule = Schedule(name: name, days: selectedDays, startHour: start, endHour: end, allDay: allDay)
        schedules.append(rule)
        Schedule.save(schedules)
        updateStatus()

        // Show manage dialog again
        handleScheduleAction()
    }

    @objc private func handleUninstall() {
        guard PasswordManager.requireAuth() else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "UnlockNotifier 제거"
        alert.informativeText = "LaunchAgent, 설정, 앱을 모두 삭제합니다. 계속하시겠습니까?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        LaunchAgent.uninstall()

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        if let appPath = Bundle.main.bundlePath as String? {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", "sleep 1; rm -rf '\(appPath)'"]
            try? proc.run()
        }

        NSApp.terminate(nil)
    }

    @objc private func testForce() { handleUnlock(bypassSchedule: true) }
    @objc private func testWithSchedule() { handleUnlock(bypassSchedule: false) }

    @objc private func openWeb() {
        guard PasswordManager.requireAuth(), !topic.isEmpty else { return }
        NSWorkspace.shared.open(URL(string: "https://ntfy.sh/\(topic)")!)
    }

    @objc private func handlePassword() {
        if PasswordManager.isSet {
            guard PasswordManager.promptVerify() else { return }
        }
        PasswordManager.promptSetup()
    }

    @objc private func handleQuit() {
        guard PasswordManager.requireAuth() else { return }
        NSApp.terminate(nil)
    }

    // MARK: Unlock Handler

    private func handleUnlock(bypassSchedule: Bool = false) {
        guard PasswordManager.isSet else {
            fputs("WARNING: Password not set, skipping\n", stderr)
            return
        }
        guard !topic.isEmpty else {
            fputs("WARNING: Topic not set, skipping\n", stderr)
            return
        }

        let now = Date()
        if !bypassSchedule {
            guard Schedule.shouldNotify(schedules: schedules, now: now) else {
                fputs("Outside schedule, skipping\n", stderr)
                return
            }
        }

        fputs("Screen unlocked at \(ISO8601DateFormatter().string(from: now))\n", stderr)

        setIcon("lock.open.trianglebadge.exclamationmark")
        statusMenuItem.title = "📤 Sending..."

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastEventMenuItem.title = "Last: \(formatter.string(from: now))"

        let path = "/tmp/unlock-\(Int(now.timeIntervalSince1970)).jpg"
        let client = NtfyClient(topic: topic)
        let title = alertTitle
        let message = alertMessage

        camera.take(to: path) { photoPath in
            client.send(photoPath: photoPath, title: title, message: message)
            if let p = photoPath { try? FileManager.default.removeItem(atPath: p) }
            DispatchQueue.main.async { self.updateStatus() }
        }
    }
}

// MARK: - NSMenu Helpers

private extension NSMenu {
    @discardableResult
    func addDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
        return item
    }

    @discardableResult
    func addActionItem(_ title: String, target: AnyObject, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        addItem(item)
        return item
    }
}

// MARK: - Main

let lockPath = "/tmp/unlock-notifier.lock"
let lockFd = open(lockPath, O_CREAT | O_WRONLY, 0o644)
if lockFd < 0 || flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
    fputs("Already running, exiting.\n", stderr)
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
