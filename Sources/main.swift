// Networth Overlay — отдельное окно с нетворсом и таймерами поверх Dota 2 на macOS.
//
// Как это работает и почему это не чит:
//  • данные приходят из официального Game State Integration (GSI): Dota сама шлёт JSON
//    на 127.0.0.1, приложение только слушает локальный порт;
//  • приложение не читает и не пишет память игры, не внедряется в её процесс,
//    не подменяет файлы игры — добавляет лишь один cfg-файл GSI;
//  • окно — обычная панель macOS поверх экрана, оно не рисует внутри игры.

import AppKit
import SwiftUI
import Network
import Carbon.HIToolbox

let gsiPort: UInt16 = 41741
let cfgName = "gamestate_integration_networth_overlay.cfg"
let dotaBundleID = "com.valvesoftware.dota2"
let steamBundleID = "com.valvesoftware.steam"
let steamApp = "/Applications/Steam.app"
let dotaCfgDir = NSHomeDirectory()
    + "/Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/cfg"
let environment = ProcessInfo.processInfo.environment

// MARK: - Окно поверх игры

/// Подложка: тянет окно мышью за любое место.
final class DragView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class OverlayPanel: NSPanel {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Панель не активирует приложение (игра не теряет фокус), видна во всех
        // пространствах, включая чужие полноэкранные, и лежит выше окна игры.
        isFloatingPanel = true
        level = .screenSaver   // после isFloatingPanel: тот сбрасывает уровень на «плавающий»
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false

        let drag = DragView()
        host.translatesAutoresizingMaskIntoConstraints = true
        drag.addSubview(host)
        contentView = drag
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show<V: View>(_ view: V) {
        host.rootView = AnyView(view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        // Держим левый верхний угол на месте, когда меняется высота.
        let topLeft = savedTopLeft() ?? defaultTopLeft()
        setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        if !isVisible { orderFrontRegardless() }
    }

    func rememberPosition() {
        UserDefaults.standard.set(Double(frame.minX), forKey: "x")
        UserDefaults.standard.set(Double(frame.maxY), forKey: "top")
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "x")
        UserDefaults.standard.removeObject(forKey: "top")
    }

    private func savedTopLeft() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: "x") != nil else { return nil }
        let p = NSPoint(x: d.double(forKey: "x"), y: d.double(forKey: "top"))
        // Если монитор отключили и точка оказалась вне экранов — вернуть по умолчанию.
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(p) } ? p : nil
    }

    private func defaultTopLeft() -> NSPoint {
        let f = (NSScreen.main ?? NSScreen.screens[0]).frame
        return NSPoint(x: f.minX + 170, y: f.maxY - 220)
    }
}

// MARK: - Приём данных от Dota (локальный HTTP)

final class GSIServer {
    private var listener: NWListener?
    var onPayload: (([String: Any]) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Слушаем только 127.0.0.1 — снаружи порт недоступен.
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: gsiPort)!)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in
                c.start(queue: .main)
                self?.read(c, buffer: Data())
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed(let e) = state { self?.onError?(tr("порт \(gsiPort) занят: \(e)", "port \(gsiPort) is busy: \(e)")) }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            onError?(tr("порт \(gsiPort): \(error)", "port \(gsiPort): \(error)"))
        }
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 8 << 20 { c.cancel(); return }

            if let split = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<split.lowerBound], as: UTF8.self).lowercased()
                var length = 0
                for line in head.split(separator: "\r\n") where line.hasPrefix("content-length:") {
                    length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
                }
                let body = buf[split.upperBound...]
                if body.count >= length {
                    if let json = try? JSONSerialization.jsonObject(with: body.prefix(length)) as? [String: Any] {
                        self?.onPayload?(json)
                    }
                    let reply = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    c.send(content: Data(reply.utf8), completion: .contentProcessed { _ in c.cancel() })
                    return
                }
            }
            if done || error != nil { c.cancel(); return }
            self?.read(c, buffer: buf)
        }
    }
}

// MARK: - Файл GSI в папке Dota

/// Кладёт конфиг, по которому Dota шлёт нам данные.
func installGSIConfig() -> (found: Bool, ok: Bool, line: String) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dotaCfgDir) else { return (false, false, tr("папка Dota 2 не найдена", "Dota 2 folder not found")) }
    let dir = dotaCfgDir + "/gamestate_integration"
    let path = dir + "/" + cfgName
    let cfg = """
    "Networth Overlay"
    {
    \t"uri"        "http://127.0.0.1:\(gsiPort)/"
    \t"timeout"    "5.0"
    \t"buffer"     "0.1"
    \t"throttle"   "0.5"
    \t"heartbeat"  "10.0"
    \t"data"
    \t{
    \t\t"provider"  "1"
    \t\t"map"       "1"
    \t\t"player"    "1"
    \t\t"hero"      "1"
    \t\t"events"    "1"
    \t\t"items"     "1"
    \t}
    }

    """
    if (try? String(contentsOfFile: path, encoding: .utf8)) == cfg { return (true, true, tr("готово", "ready")) }
    do {
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try cfg.write(toFile: path, atomically: true, encoding: .utf8)
        return (true, true, tr("файл настроек записан — если Dota уже открыта, перезапустите её", "config file written — if Dota is already open, restart it"))
    } catch {
        return (true, false, tr("файл настроек не записан: \(error.localizedDescription)", "config file not written: \(error.localizedDescription)"))
    }
}

// MARK: - Запуск Dota через Steam

/// Запускает Dota 2 так же, как это делает сам Steam, добавляя параметр GSI.
func launchDota() {
    let args = ["-applaunch", "570", "-gamestateintegration"]
    let binary = steamApp + "/Contents/MacOS/steam_osx"
    let steamRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: steamBundleID).isEmpty

    if steamRunning, FileManager.default.isExecutableFile(atPath: binary) {
        // Второй экземпляр Steam передаёт команду уже запущенному и сразу выходит.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil { return }
    }
    if FileManager.default.fileExists(atPath: steamApp) {
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: steamApp), configuration: config)
        return
    }
    if let url = URL(string: "steam://rungameid/570") { NSWorkspace.shared.open(url) }
}

// MARK: - Горячая клавиша Ctrl+Shift+H

var hotkeyAction: (() -> Void)?

func registerHotkey() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        hotkeyAction?()
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | shiftKey),
                        EventHotKeyID(signature: OSType(0x4E57_4F56), id: 1),
                        GetApplicationEventTarget(), 0, &ref)
}

// MARK: - Приложение

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = Store()
    private let model = AppModel()
    private let data = OpenData()
    private let panel = OverlayPanel()
    private let server = GSIServer()
    private let match = MatchState()
    private let alerts = Alerts()
    private let updater = Updater()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    private var lastFrame: Frame?
    private var lastHint: String?
    private var lastData = Date.distantPast
    private var hiddenByHotkey = false
    private var shownLanguage: String?

    func applicationDidFinishLaunching(_ note: Notification) {
        panel.delegate = self
        data.enabled = store.s.openData
        data.onUpdate = { [weak self] in
            // Счётчик заставляет SwiftUI перерисовать окна: сам справочник — класс, его изменения не видны.
            self?.model.dataRevision += 1
            self?.redraw()
        }
        data.loadConstants()
        data.prepare(heroID: demoFrame().heroID)   // чтобы в примере в настройках сразу были сборка и портрет

        shownLanguage = store.s.language
        let gsi = installGSIConfig()
        model.dotaFound = gsi.found
        model.gsiOK = gsi.ok
        model.gsiLine = gsi.line
        model.myHeroID = UserDefaults.standard.integer(forKey: "lastHeroID")

        match.itemCost = { [weak self] in self?.data.cost(ofItem: $0) }
        match.onMatchEnd = { [weak self] id in
            UserDefaults.standard.set(id, forKey: "lastMatchID")
            // OpenDota узнаёт о матче не сразу — спрашиваем чуть позже.
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { self?.loadLastMatch() }
        }
        alerts.playSound = { [weak self] metric in self?.beep(metric) }

        model.play = { launchDota() }
        model.toggleReposition = { [weak self] in
            guard let self else { return }
            self.model.repositioning.toggle()
            self.redraw()
        }
        model.resetPosition = { [weak self] in
            self?.panel.resetPosition()
            self?.redraw()
        }
        model.testSound = { [weak self] metric in self?.beep(metric) }
        model.loadLastMatch = { [weak self] in self?.loadLastMatch() }
        model.version = updater.current
        model.viaBrew = updater.installedViaBrew
        model.checkUpdate = { [weak self] in self?.checkUpdate(auto: false) }
        model.installUpdate = { [weak self] in self?.installUpdate() }

        store.onChange = { [weak self] in
            guard let self else { return }
            self.data.enabled = self.store.s.openData
            if self.store.s.language != self.shownLanguage {
                // Сменили язык: обновляем тексты, которые были составлены заранее.
                self.shownLanguage = self.store.s.language
                self.buildMenu()
                self.model.gsiLine = installGSIConfig().line
                if !self.model.dataOK { self.model.dataLine = tr("ещё не приходили", "none yet") }
                self.checkUpdate(auto: false)
            }
            self.redraw()
        }

        server.onPayload = { [weak self] json in self?.handle(json) }
        server.onError = { [weak self] text in
            self?.model.gsiOK = false
            self?.model.gsiLine = text
        }
        server.start()

        hotkeyAction = { [weak self] in
            guard let self else { return }
            self.hiddenByHotkey.toggle()
            self.redraw()
        }
        registerHotkey()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appsChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }

        buildMenu()
        tick()
        checkUpdate(auto: true)
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkUpdate(auto: true) }
        loadLastMatch()
        if CommandLine.arguments.contains("--demo") { model.repositioning = true; redraw() }
        if !CommandLine.arguments.contains("--background") { showSettings() }
        snapshotSettingsIfAsked()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Данные

    private func handle(_ json: [String: Any]) {
        lastData = Date()
        model.dataOK = true
        guard let frame = match.ingest(json, turbo: store.s.turbo) else {
            lastFrame = nil
            lastHint = nil
            model.dataLine = tr("Dota на связи, матч не идёт", "Dota connected, no match in progress")
            redraw()
            return
        }
        model.dataLine = (frame.spectator ? tr("режим зрителя, ", "spectating, ") : tr("идёт матч, ", "match in progress, ")) + mmss(frame.clock)
        if let hero = frame.heroID, hero != model.myHeroID {
            model.myHeroID = hero
            UserDefaults.standard.set(hero, forKey: "lastHeroID")
        }
        data.prepare(heroID: frame.heroID)
        lastFrame = frame
        lastHint = alerts.update(frame, settings: store.s)
        redraw()
    }

    private func tick() {
        model.dotaRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: dotaBundleID).isEmpty
        if lastFrame != nil, Date().timeIntervalSince(lastData) > 30 {
            // Dota замолчала: матч кончился или игру закрыли.
            lastFrame = nil
            lastHint = nil
            model.dataOK = false
            model.dataLine = tr("нет данных больше 30 с", "no data for over 30 s")
        }
        redraw()
    }

    @objc private func appsChanged() { redraw() }

    private var dotaIsFront: Bool {
        if environment["NWO_ANYAPP"] != nil { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == dotaBundleID
    }

    private func redraw() {
        let s = store.s
        panel.ignoresMouseEvents = s.clickThrough && !model.repositioning

        if model.repositioning {
            data.prepare(heroID: demoFrame().heroID)
            panel.show(OverlayContent(frame: demoFrame(), settings: s, hint: tr("Эгида пропадёт через 55 с", "Aegis expires in 55 s"), data: data, revision: model.dataRevision))
        } else if s.enabled, !hiddenByHotkey, let frame = lastFrame, !s.onlyWhenDotaFront || dotaIsFront {
            panel.show(OverlayContent(frame: frame, settings: s, hint: lastHint, data: data, revision: model.dataRevision))
        } else {
            panel.orderOut(nil)
            return
        }
        snapshotOverlayIfAsked()
    }

    private func loadLastMatch() {
        let id = environment["NWO_MATCH"] ?? UserDefaults.standard.string(forKey: "lastMatchID") ?? ""
        guard !id.isEmpty else { return }
        guard store.s.openData else { model.lastMatchNote = tr("Итоги берутся с OpenDota — включите эту настройку.", "Results come from OpenDota — turn that setting on."); return }
        model.lastMatchNote = tr("Матч \(id): запрашиваю итоги…", "Match \(id): requesting results…")
        data.fetchMatch(id) { [weak self] summary in
            guard let self else { return }
            if let summary {
                self.model.lastMatch = summary
            } else if self.model.lastMatch?.id != id {
                self.model.lastMatch = nil
                self.model.lastMatchNote = tr("Матч \(id): итогов на OpenDota пока нет — нажмите «Обновить итоги» через пару минут.", "Match \(id): no results on OpenDota yet — press “Refresh results” in a couple of minutes.")
            }
            self.snapshotSettingsIfAsked()
        }
    }

    // MARK: Обновления

    private func checkUpdate(auto: Bool) {
        guard updater.configured else { model.updateLine = tr("— сборка без адреса репозитория, проверка отключена", "— built without a repository address, update check is off"); return }
        model.updateLine = tr("— проверяю…", "— checking…")
        updater.check { [weak self] newer, failed in
            guard let self else { return }
            self.model.newVersion = newer
            if failed {
                self.model.updateLine = tr("— не удалось проверить обновления", "— could not check for updates")
            } else if let newer {
                self.model.updateLine = tr("— доступна версия \(newer)", "— version \(newer) is available")
                // Сами ставим только раз на версию и не во время игры: иначе при сбое brew был бы бесконечный перезапуск.
                let tried = UserDefaults.standard.string(forKey: "updateTried")
                if auto, self.store.s.autoUpdate ?? true, self.updater.installedViaBrew, !self.model.dotaRunning, tried != newer {
                    UserDefaults.standard.set(newer, forKey: "updateTried")
                    self.installUpdate()
                }
            } else {
                self.model.updateLine = tr("— последняя", "— up to date")
            }
        }
    }

    private func installUpdate() {
        if updater.installWithBrew() {
            model.updateLine = tr("— обновляю через Homebrew, приложение перезапустится", "— updating via Homebrew, the app will restart")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        } else if let url = updater.releasesURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func beep(_ metric: Metric) {
        guard let sound = NSSound(named: store.s.soundName(metric))?.copy() as? NSSound else { return }
        sound.volume = Float(store.s.volume)
        sound.play()
    }

    // MARK: Окна и меню

    private func buildMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "NW"
        }
        let menu = NSMenu()
        menu.addItem(item(tr("Играть в Dota 2", "Play Dota 2"), #selector(play)))
        menu.addItem(item(tr("Настройки…", "Settings…"), #selector(showSettings)))
        menu.addItem(item(tr("Спрятать или показать окно (Ctrl+Shift+H)", "Hide or show the window (Ctrl+Shift+H)"), #selector(toggleHidden)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Выйти", "Quit"), #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func play() { launchDota() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggleHidden() { hotkeyAction?() }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Networth Overlay"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store, model: model, data: data))
            window.setContentSize(NSSize(width: 980, height: 760))
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        data.prepare(heroID: demoFrame().heroID)   // чтобы в примере были сборка и портрет
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === panel { panel.rememberPosition() }
    }

    func windowWillClose(_ notification: Notification) {
        // Закрыли настройки — пример для перестановки больше не нужен.
        if notification.object as? NSWindow === settingsWindow, model.repositioning {
            model.repositioning = false
            redraw()
        }
    }

    // MARK: Самопроверка: NWO_SNAPSHOT / NWO_SETTINGS_SNAPSHOT сохраняют картинки окон

    private func snapshotOverlayIfAsked() {
        guard let path = environment["NWO_SNAPSHOT"], let view = panel.contentView else { return }
        save(view, to: path)
    }

    private func snapshotSettingsIfAsked() {
        guard let path = environment["NWO_SETTINGS_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            // Рисуем всё содержимое настроек без прокрутки в отдельном окне за экраном.
            let view = SettingsView(store: self.store, model: self.model, data: self.data).content.frame(width: 1040).background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.save(host, to: path)
                window.orderOut(nil)
            }
        }
    }

    private func save(_ view: NSView, to path: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // без значка в Dock, не перехватывает фокус у игры
app.run()
