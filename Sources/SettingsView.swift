// Окно настроек.

import SwiftUI

final class AppModel: ObservableObject {
    @Published var dotaFound = false
    @Published var gsiLine = ""
    @Published var gsiOK = false
    @Published var dotaRunning = false
    @Published var dataLine = tr("ещё не приходили", "none yet")
    @Published var dataOK = false
    @Published var lastMatch: MatchSummary?
    @Published var lastMatchNote = ""
    @Published var myHeroID = 0
    @Published var repositioning = false
    @Published var dataRevision = 0
    @Published var version = ""
    @Published var updateLine = ""
    @Published var newVersion: String?
    @Published var viaBrew = false

    var play: () -> Void = {}
    var toggleReposition: () -> Void = {}
    var resetPosition: () -> Void = {}
    var testSound: (Metric) -> Void = { _ in }
    var loadLastMatch: () -> Void = {}
    var checkUpdate: () -> Void = {}
    var installUpdate: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var model: AppModel
    let data: OpenData

    var body: some View {
        ScrollView { content }
            .frame(minWidth: 860, minHeight: 620)
    }

    /// Всё содержимое без прокрутки (так же используется для снимка при самопроверке).
    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            windowCard
            metricsCard
            soundCard
            lastMatchCard
            updateCard
            aboutCard
        }
        .padding(20)
    }

    // MARK: Состояние и запуск

    private var statusCard: some View {
        card(tr("Нетворс в игре", "Net worth in game")) {
            Text(tr("Показывает ваш нетворс, таймеры и другие цифры поверх Dota 2 во время матча. Только ваши собственные данные из официального Game State Integration — без чтения памяти игры.", "Shows your net worth, timers and other numbers on top of Dota 2 during a match. Only your own data from the official Game State Integration — no reading of game memory."))
                .foregroundColor(.secondary)
            statusRow(tr("Функция", "Overlay"), store.s.enabled ? tr("включена", "on") : tr("выключена", "off"), store.s.enabled ? .green : .gray)
            statusRow(tr("Dota 2 на компьютере", "Dota 2 on this Mac"), model.dotaFound ? tr("найдена", "found") : tr("не найдена в папке Steam", "not found in the Steam folder"), model.dotaFound ? .green : .red)
            statusRow(tr("Подключение к игре", "Game connection"), model.gsiLine, model.gsiOK ? .green : .red)
            statusRow(tr("Запуск игры", "Game"), model.dotaRunning ? tr("Dota 2 запущена", "Dota 2 is running") : tr("Dota 2 не запущена", "Dota 2 is not running"), model.dotaRunning ? .green : .gray)
            statusRow(tr("Данные из игры", "Game data"), model.dataLine, model.dataOK ? .green : .red)
            HStack {
                Button(action: model.play) { Label(tr("Играть", "Play"), systemImage: "play.fill").padding(.horizontal, 8) }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button(store.s.enabled ? tr("Выключить", "Turn off") : tr("Включить", "Turn on")) { store.s.enabled.toggle() }
                    .controlSize(.large)
                Text(tr("«Играть» запускает Dota 2 через Steam с параметром -gamestateintegration.", "“Play” launches Dota 2 through Steam with the -gamestateintegration option."))
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func statusRow(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).fontWeight(.semibold).frame(width: 190, alignment: .leading)
            Text(value).foregroundColor(.secondary)
        }
    }

    // MARK: Окно поверх игры

    private var windowCard: some View {
        card(tr("Окно поверх игры", "Overlay window")) {
            Text(tr("Пример: 19:15 матча. В игре строки без данных скрыты: Рошан — после его смерти, «На 10:00» — после 10:00.", "Example: 19:15 into a match. In game, rows without data are hidden: Roshan — after he dies, “At 10:00” — after 10:00."))
                .font(.caption).foregroundColor(.secondary)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.25, green: 0.22, blue: 0.1), Color(red: 0.12, green: 0.22, blue: 0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                OverlayContent(frame: demoFrame(), settings: store.s, hint: tr("Эгида пропадёт через 55 с", "Aegis expires in 55 s"), data: data, revision: model.dataRevision)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            option(tr("Язык", "Language")) {
                Picker("", selection: Binding(get: { store.s.language ?? "auto" },
                                              set: { store.s.language = $0 == "auto" ? nil : $0 })) {
                    Text(tr("Как в системе", "System")).tag("auto")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
            }
            option(tr("Размер", "Size")) {
                Picker("", selection: $store.s.size) {
                    ForEach(Presets.names, id: \.id) { Text($0.title).tag($0.id) }
                }
            }
            Text(tr("Мини — нетворс, GPM и XPM; маленький — самое главное; средний — больше данных; крупный — всё. «Свой» — ваш выбор показателей ниже.", "Mini — net worth, GPM and XPM; small — the essentials; medium — more data; large — everything. “Custom” — your own selection below."))
                .font(.caption).foregroundColor(.secondary).padding(.leading, 120)
            option(tr("Раскладка", "Layout")) {
                Picker("", selection: $store.s.column) {
                    Text(tr("Сеткой", "Grid")).tag(false)
                    Text(tr("В столбик", "Column")).tag(true)
                }
            }
            option(tr("Прозрачность", "Transparency")) {
                Picker("", selection: $store.s.opacity) {
                    ForEach([0.0, 0.2, 0.4, 0.6, 0.8], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
            }
            option(tr("Масштаб", "Scale")) {
                Picker("", selection: $store.s.scale) {
                    ForEach([0.9, 1.0, 1.2], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
            }
            option(tr("Вид", "View")) {
                Picker("", selection: $store.s.detailed) {
                    Text(tr("Компактный", "Compact")).tag(false)
                    Text(tr("Подробный", "Detailed")).tag(true)
                }
            }
            Toggle(tr("Клики сквозь окно — в игре окно совсем не ловит мышь", "Click-through — the window ignores the mouse in game"), isOn: $store.s.clickThrough)
            Toggle(tr("Показывать только когда Dota 2 на экране", "Show only while Dota 2 is in front"), isOn: $store.s.onlyWhenDotaFront)
            Toggle(tr("Режим Turbo — другие сроки Рошана и Эгиды (игра этот режим не сообщает)", "Turbo mode — different Roshan and Aegis timings (the game does not report this mode)"), isOn: $store.s.turbo)
            Toggle(tr("Брать сборки, обычный GPM/XPM героя и итоги матча с OpenDota", "Get builds, typical hero GPM/XPM and match results from OpenDota"), isOn: $store.s.openData)
            HStack {
                Button(model.repositioning ? tr("Готово, спрятать пример", "Done, hide the example") : tr("Переставить окно", "Move the window"), action: model.toggleReposition)
                Button(tr("Вернуть на место", "Reset position"), action: model.resetPosition)
                Text(tr("Окно перетаскивается мышью за любое место. Ctrl+Shift+H — спрятать или показать окно в игре.", "Drag the window anywhere with the mouse. Ctrl+Shift+H hides or shows it in game."))
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func option<P: View>(_ title: String, @ViewBuilder picker: () -> P) -> some View {
        HStack {
            Text(title).foregroundColor(.secondary).frame(width: 112, alignment: .leading)
            picker().pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    // MARK: Показатели

    private var metricsCard: some View {
        card(tr("Показатели в окне", "What the window shows")) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(MetricGroup.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title.uppercased()).font(.caption).foregroundColor(.secondary)
                        ForEach(Metric.allCases.filter { $0.group == group }) { metric in
                            Toggle(isOn: shown(metric)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(metric.title).fontWeight(.semibold)
                                    Text(metric.about).font(.caption).foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// Галочка показателя: любое изменение переводит размер в «Свой».
    private func shown(_ metric: Metric) -> Binding<Bool> {
        Binding(
            get: { store.s.shown.contains(metric) },
            set: { on in
                var set = store.s.shown
                if on { set.insert(metric) } else { set.remove(metric) }
                var next = store.s
                next.custom = set
                next.size = "custom"
                store.s = next
            })
    }

    // MARK: Звук

    private var soundCard: some View {
        card(tr("Звуковые напоминания", "Sound reminders")) {
            Toggle(isOn: $store.s.sound) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Сигнал перед событиями", "Sound before events")).fontWeight(.semibold)
                    Text(tr("Короткий звук в тот момент, когда таймер в окне становится жёлтым: перед рунами, стаком и Терзателем, а ещё когда Рошан может появиться.", "A short sound at the moment a timer turns yellow: before runes, stacks and Tormentor, and when Roshan may respawn."))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            HStack {
                Text(tr("Громкость", "Volume")).foregroundColor(.secondary)
                Slider(value: $store.s.volume, in: 0...1).frame(width: 180)
                Text("\(Int(store.s.volume * 100))%").foregroundColor(.secondary).monospacedDigit()
            }
            Text(tr("Для каждого события — свой звук: по сигналу слышно, что именно скоро произойдёт. ▶ — прослушать.", "Each event has its own sound, so you can tell what is coming by ear. ▶ — preview."))
                .font(.caption).foregroundColor(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Sounds.events) { metric in
                    GridRow {
                        Toggle(metric == .aegis ? tr("Конец Эгиды", "Aegis expiring") : metric.title, isOn: soundEvent(metric))
                        Picker("", selection: soundName(metric)) {
                            ForEach(Sounds.all, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(width: 130)
                        Button("▶") { model.testSound(metric) }
                    }
                }
            }
            .disabled(!store.s.sound)
        }
    }

    private func soundName(_ metric: Metric) -> Binding<String> {
        Binding(
            get: { store.s.soundName(metric) },
            set: { name in
                var names = store.s.soundNames ?? [:]
                names[metric.rawValue] = name
                store.s.soundNames = names
                model.testSound(metric)   // сразу слышно, что выбрали
            })
    }

    private func soundEvent(_ metric: Metric) -> Binding<Bool> {
        Binding(
            get: { store.s.soundEvents.contains(metric) },
            set: { on in
                if on { store.s.soundEvents.insert(metric) } else { store.s.soundEvents.remove(metric) }
            })
    }

    // MARK: Последний матч

    private var lastMatchCard: some View {
        card(tr("Последний матч", "Last match")) {
            if let match = model.lastMatch {
                let radiant = match.players.filter { $0.radiant }
                let dire = match.players.filter { !$0.radiant }
                let diff = abs(radiant.reduce(0) { $0 + $1.netWorth } - dire.reduce(0) { $0 + $1.netWorth })
                Text(tr("Матч \(match.id) · Победа ", "Match \(match.id) · ") + (match.radiantWin ? tr("Сил Света", "Radiant victory") : tr("Сил Тьмы", "Dire victory")) + " · \(mmss(Double(match.duration))) · " + tr("Разница в нетворсе: ", "Net worth difference: ") + String(diff))
                    .foregroundColor(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    team(tr("Силы Света", "Radiant"), radiant, score: match.radiantScore, won: match.radiantWin, color: .green)
                    team(tr("Силы Тьмы", "Dire"), dire, score: match.direScore, won: !match.radiantWin, color: .red)
                }
            } else {
                Text(model.lastMatchNote.isEmpty ? tr("Появится после первого сыгранного матча.", "Appears after your first match.") : model.lastMatchNote)
                    .foregroundColor(.secondary)
            }
            Button(tr("Обновить итоги", "Refresh results"), action: model.loadLastMatch)
        }
    }

    private func team(_ title: String, _ players: [MatchPlayer], score: Int, won: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).fontWeight(.bold)
                if won { Text(tr("Победа", "Victory")).foregroundColor(Palette.gold).fontWeight(.semibold) }
                Text(tr("Нетворс ", "Net worth ") + String(players.reduce(0) { $0 + $1.netWorth }) + tr(" · Убийства ", " · Kills ") + String(score))
                    .font(.caption).foregroundColor(.secondary)
            }
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text(tr("Герой", "Hero")).gridColumnAlignment(.leading)
                    Text("K / D / A"); Text(tr("Нетворс", "Net worth")); Text(tr("Золото", "Gold")); Text("GPM"); Text("XPM"); Text(tr("Доб. / не отд.", "LH / DN"))
                }
                .font(.caption).foregroundColor(.secondary)
                ForEach(players) { p in
                    GridRow {
                        Text(p.hero).gridColumnAlignment(.leading)
                        Text("\(p.kills) / \(p.deaths) / \(p.assists)")
                        Text(String(p.netWorth)); Text(String(p.gold)); Text(String(p.gpm)); Text(String(p.xpm))
                        Text("\(p.lastHits) / \(p.denies)")
                    }
                    .foregroundColor(p.heroID == model.myHeroID ? Palette.gold : .primary)
                    .monospacedDigit()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .background(Color.primary.opacity(0.04))
    }

    private var updateCard: some View {
        card(tr("Обновления", "Updates")) {
            HStack {
                Text(tr("Версия \(model.version)", "Version \(model.version)")).fontWeight(.semibold)
                Text(model.updateLine).foregroundColor(.secondary)
            }
            Toggle(tr("Обновлять автоматически через Homebrew (не во время игры)", "Update automatically via Homebrew (never during a game)"), isOn: Binding(
                get: { store.s.autoUpdate ?? true },
                set: { store.s.autoUpdate = $0 }))
                .disabled(!model.viaBrew)
            if !model.viaBrew {
                Text(tr("Автообновление работает, когда приложение установлено через Homebrew: brew install --cask networth-overlay", "Auto-update works when the app is installed via Homebrew: brew install --cask networth-overlay"))
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Button(tr("Проверить обновления", "Check for updates"), action: model.checkUpdate)
                if let version = model.newVersion {
                    Button(model.viaBrew ? tr("Обновить до \(version)", "Update to \(version)") : tr("Скачать \(version)", "Download \(version)"), action: model.installUpdate)
                }
            }
        }
    }

    private var aboutCard: some View {
        card(tr("Откуда данные", "Where the data comes from")) {
            Text(tr("• Game State Integration — официальный механизм Valve: Dota 2 сама отправляет данные вашего героя на локальный адрес 127.0.0.1. Приложение не читает и не меняет память игры, не внедряется в её процесс и не трогает файлы игры, кроме одного файла настроек GSI в папке cfg.", "• Game State Integration is Valve's official mechanism: Dota 2 itself sends your hero's data to the local address 127.0.0.1. The app does not read or modify game memory, does not inject into the game process and does not touch game files, except for one GSI config file in the cfg folder."))
            Text(tr("• OpenDota — открытая статистика: названия предметов и героев, популярные сборки, обычные GPM/XPM, итоги матча. В запросах уходит только номер героя или матча.", "• OpenDota is open statistics: item and hero names, popular builds, typical GPM/XPM, match results. Requests carry only a hero or match number."))
            Text(tr("• Чужой нетворс во время вашего матча не показывается: игра его не отдаёт. Обе команды видны только в режиме зрителя и в итогах после матча.", "• Enemy net worth is not shown during your match: the game does not provide it. Both teams are visible only when spectating and in post-match results."))
        }
        .font(.callout)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
