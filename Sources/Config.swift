// Настройки и список показателей.

import Foundation
import Combine

/// Язык интерфейса. Все тексты в коде записаны парой tr("по-русски", "in English").
enum Lang {
    static var russian = Lang.systemIsRussian
    static var systemIsRussian: Bool { (Locale.preferredLanguages.first ?? "en").hasPrefix("ru") }
    static func apply(_ code: String?) {
        let code = ProcessInfo.processInfo.environment["NWO_LANG"] ?? code   // для самопроверки
        switch code {
        case "ru": russian = true
        case "en": russian = false
        default: russian = systemIsRussian
        }
    }
}

func tr(_ ru: String, _ en: String) -> String { Lang.russian ? ru : en }

enum MetricGroup: String, CaseIterable {
    case header, stats, timers, help

    var title: String {
        switch self {
        case .header: return tr("Строка нетворса", "Net worth row")
        case .stats: return tr("Показатели", "Stats")
        case .timers: return tr("Таймеры", "Timers")
        case .help: return tr("Помощь в игре", "In-game help")
        }
    }
}

enum Metric: String, CaseIterable, Codable, Identifiable {
    case nw, gpm, xpm
    case gold, buyback, score, participation, streak, lhpm, at10, apm, sources, farm, fromKills, income, heroGpm, heroXpm, wards
    case power, bounty, wisdom, lotus, stack, daynight, tormentor, roshan, aegis
    case build, hints, hero

    var id: String { rawValue }

    var group: MetricGroup {
        switch self {
        case .nw, .gpm, .xpm: return .header
        case .power, .bounty, .wisdom, .lotus, .stack, .daynight, .tormentor, .roshan, .aegis: return .timers
        case .build, .hints, .hero: return .help
        default: return .stats
        }
    }

    var title: String {
        switch self {
        case .nw: return tr("Нетворс", "Net worth")
        case .gpm: return "GPM"
        case .xpm: return "XPM"
        case .gold: return tr("Золото", "Gold")
        case .buyback: return tr("Выкуп", "Buyback")
        case .score: return tr("Счёт", "Score")
        case .participation: return tr("Участие", "Kill part.")
        case .streak: return tr("Серия", "Streak")
        case .lhpm: return tr("Доб./мин", "LH/min")
        case .at10: return tr("На 10:00", "At 10:00")
        case .apm: return "APM"
        case .sources: return tr("Фарм/бой/доход", "Farm/fight/passive")
        case .farm: return tr("Фарм", "Farm")
        case .fromKills: return tr("С убийств", "From kills")
        case .income: return tr("Доход", "Passive")
        case .heroGpm: return tr("GPM героя", "Hero GPM")
        case .heroXpm: return tr("XPM героя", "Hero XPM")
        case .wards: return tr("Варды", "Wards")
        case .power: return tr("Руны усиления", "Power runes")
        case .bounty: return tr("Руны богатства", "Bounty runes")
        case .wisdom: return tr("Мудрость", "Wisdom")
        case .lotus: return tr("Лотосы", "Lotus")
        case .stack: return tr("Стак", "Stack")
        case .daynight: return tr("День и ночь", "Day/night")
        case .tormentor: return tr("Терзатель", "Tormentor")
        case .roshan: return tr("Рошан", "Roshan")
        case .aegis: return tr("Эгида до", "Aegis until")
        case .build: return tr("Сборка предметов", "Item build")
        case .hints: return tr("Подсказки", "Hints")
        case .hero: return tr("Герой", "Hero")
        }
    }

    var about: String {
        switch self {
        case .nw: return tr("Стоимость героя: золото и все предметы.", "Hero value: gold plus all items.")
        case .gpm: return tr("Золото в минуту. После 20:00 стрелка ▲▼ — выше или ниже обычного для героя.", "Gold per minute. After 20:00 an arrow ▲▼ shows above or below typical for the hero.")
        case .xpm: return tr("Опыт в минуту. После 20:00 стрелка ▲▼ — выше или ниже обычного для героя.", "Experience per minute. After 20:00 an arrow ▲▼ shows above or below typical for the hero.")
        case .gold: return tr("Золото в кошельке прямо сейчас.", "Gold you have right now.")
        case .buyback: return tr("Цена выкупа: ✓ — золота хватает, −N — сколько не хватает, кд — выкуп на перезарядке.", "Buyback cost: ✓ — you can afford it, −N — how much is missing, cd — buyback on cooldown.")
        case .score: return tr("Убийства вашей команды и противника.", "Kills of your team and the enemy.")
        case .participation: return tr("Ваши убийства и помощь от всех убийств команды.", "Your kills and assists as a share of team kills.")
        case .streak: return tr("Убийств подряд без смерти. С трёх подсвечивается.", "Kills in a row without dying. Highlighted from three.")
        case .lhpm: return tr("Добивания в минуту.", "Last hits per minute.")
        case .at10: return tr("Итог стадии линий: добивания / не отданные · нетворс на 10:00.", "Laning result: last hits / denies · net worth at 10:00.")
        case .apm: return tr("Действий в минуту — сколько команд вы отдаёте герою.", "Actions per minute — how many commands you issue.")
        case .sources: return tr("Откуда золото, в процентах: фарм крипов, убийства героев, пассивный доход.", "Where gold comes from, in percent: creeps, hero kills, passive income.")
        case .farm: return tr("Сколько золота вы нафармили за матч на крипах.", "Gold earned from creeps this match.")
        case .fromKills: return tr("Золото за убийства героев и помощь в них.", "Gold from hero kills and assists.")
        case .income: return tr("Пассивный доход за матч.", "Passive income this match.")
        case .heroGpm: return tr("Обычный GPM этого героя к концу матча (медиана OpenDota).", "Typical end-of-match GPM for this hero (OpenDota median).")
        case .heroXpm: return tr("Обычный XPM этого героя к концу матча (медиана OpenDota).", "Typical end-of-match XPM for this hero (OpenDota median).")
        case .wards: return tr("Когда в лавке появится следующий Observer Ward; ✓ — уже есть.", "When the next Observer Ward restocks; ✓ — in stock.")
        case .power: return tr("До рун усиления на реке.", "Time to power runes in the river.")
        case .bounty: return tr("До рун богатства.", "Time to bounty runes.")
        case .wisdom: return tr("До рун мудрости.", "Time to wisdom runes.")
        case .lotus: return tr("До лотосов в прудах.", "Time to lotuses in the pools.")
        case .stack: return tr("До момента отвести лагерь (:53).", "Time to pull the camp for a stack (:53).")
        case .daynight: return tr("Сколько осталось до смены дня и ночи.", "Time until day/night changes.")
        case .tormentor: return tr("До появления Терзателя (20:00).", "Time until Tormentor spawns (20:00).")
        case .roshan: return tr("Окно возрождения Рошана: 8–11 минут после смерти, в Turbo — 4–5,5.", "Roshan respawn window: 8–11 minutes after death, 4–5.5 in Turbo.")
        case .aegis: return tr("Эгида действует 5 минут после того, как её подняли, в Turbo — 4.", "Aegis lasts 5 minutes after pickup, 4 in Turbo.")
        case .build: return tr("Иконки популярных предметов героя по фазам матча (OpenDota). Купленное отмечается ✓.", "Icons of popular items for the hero by game stage (OpenDota). Owned items get a ✓.")
        case .hero: return tr("Портрет и имя героя, за которого вы играете.", "Portrait and name of the hero you are playing.")
        case .hints: return tr("Короткая строка в окне: «Руны усиления через 20 с», «Не хватает 640 на выкуп».", "A short line in the window: “Power runes in 20 s”, “640 short of buyback”.")
        }
    }
}

enum Presets {
    static let mini: Set<Metric> = [.nw, .gpm, .xpm]
    static let small: Set<Metric> = mini.union([.buyback, .power, .bounty, .roshan, .aegis, .build, .hints, .hero])
    static let medium: Set<Metric> = small.union([.gold, .score, .lhpm, .wisdom, .lotus, .stack, .tormentor])
    static let large: Set<Metric> = Set(Metric.allCases)
    static var names: [(id: String, title: String)] { [
        ("mini", tr("Мини", "Mini")), ("small", tr("Маленький", "Small")), ("medium", tr("Средний", "Medium")), ("large", tr("Крупный", "Large")), ("custom", tr("Свой", "Custom")),
    ] }
    static func set(_ id: String) -> Set<Metric>? {
        switch id {
        case "mini": return mini
        case "small": return small
        case "medium": return medium
        case "large": return large
        default: return nil
        }
    }
}

/// Системные звуки macOS (/System/Library/Sounds) и звук по умолчанию для каждого события.
enum Sounds {
    static let all = ["Glass", "Ping", "Tink", "Pop", "Purr", "Hero", "Submarine", "Blow", "Bottle",
                      "Frog", "Funk", "Morse", "Sosumi", "Basso"]
    static let events: [Metric] = [.power, .bounty, .wisdom, .lotus, .stack, .tormentor, .roshan, .aegis, .daynight]
    static let defaults: [Metric: String] = [
        .power: "Glass", .bounty: "Ping", .wisdom: "Purr", .lotus: "Pop", .stack: "Tink",
        .tormentor: "Submarine", .roshan: "Hero", .aegis: "Sosumi", .daynight: "Blow",
    ]
}

struct Settings: Codable, Equatable {
    var enabled = true
    var size = "small"
    var custom: Set<Metric> = Presets.small
    var column = false
    var opacity = 0.0          // 0…0.8 — прозрачность фона
    var scale = 1.0
    var detailed = true
    var clickThrough = false
    var onlyWhenDotaFront = true
    var turbo = false
    var openData = true        // запросы к OpenDota
    var sound = false
    var volume = 0.6
    var soundEvents: Set<Metric> = [.power, .bounty, .wisdom, .stack, .tormentor, .roshan]
    /// Свой звук для события (ключ — Metric.rawValue). Необязательное поле: старые настройки читаются без него.
    var soundNames: [String: String]?
    /// Язык интерфейса: "ru", "en" или nil — как в системе.
    var language: String?
    /// Ставить новые версии самому (через Homebrew). nil — как true.
    var autoUpdate: Bool?

    func soundName(_ m: Metric) -> String { soundNames?[m.rawValue] ?? Sounds.defaults[m] ?? "Glass" }

    var shown: Set<Metric> { Presets.set(size) ?? custom }
}

final class Store: ObservableObject {
    @Published var s: Settings {
        didSet {
            guard s != oldValue else { return }
            Lang.apply(s.language)
            if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "settings") }
            onChange?()
        }
    }
    var onChange: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            s = saved
        } else {
            s = Settings()
        }
        Lang.apply(s.language)
    }
}
