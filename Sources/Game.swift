// Разбор данных Game State Integration, таймеры и напоминания.
// Всё, что здесь используется, Dota сама отдаёт наружу по официальному GSI:
// только данные своего героя и общие часы матча.

import Foundation

struct TeamWorth {
    var name: String
    var total: Int
    var heroes: [(name: String, worth: Int)]
}

struct Frame {
    var clock = 0.0
    var matchID = ""
    var spectator = false
    var heroID: Int?
    var netWorth: Int?
    var gold: Int?
    var gpm: Int?
    var xpm: Int?
    var kills: Int?
    var deaths: Int?
    var assists: Int?
    var lastHits: Int?
    var denies: Int?
    var streak: Int?
    var commands: Int?
    var goldCreeps: Int?
    var goldHeroes: Int?
    var goldIncome: Int?
    var buybackCost: Int?
    var buybackCooldown: Double?
    var alive: Bool?
    var respawn: Double?
    var scoreOurs: Int?
    var scoreTheirs: Int?
    var wardCooldown: Double?
    var roshan: (from: Double, to: Double)?
    var aegisUntil: Double?
    var at10: (lh: Int, dn: Int, nw: Int)?
    var items: Set<String> = []
    var teams: [TeamWorth] = []

    var minutes: Double { max(clock, 1) / 60 }
}

enum Rules {
    static func aegis(turbo: Bool) -> Double { turbo ? 240 : 300 }
    static func roshan(turbo: Bool) -> (min: Double, max: Double) { turbo ? (240, 330) : (480, 660) }
    static func buybackHintFrom(turbo: Bool) -> Double { turbo ? 900 : 1800 }

    /// (первое появление, период, за сколько секунд предупреждать). Период 0 — событие одно.
    static func timer(_ m: Metric) -> (first: Double, every: Double, warn: Double)? {
        switch m {
        case .power: return (120, 120, 20)      // 2:00 и 4:00 — руны воды, дальше усиления
        case .bounty: return (240, 240, 20)
        case .wisdom: return (420, 420, 30)
        case .lotus: return (180, 180, 15)
        case .stack: return (113, 60, 10)       // лагеря появляются в 1:00, первый стак в 1:53
        case .daynight: return (300, 300, 20)
        case .tormentor: return (1200, 0, 60)
        default: return nil
        }
    }

    /// Время следующего события по часам матча; nil — больше не будет.
    static func next(_ m: Metric, clock: Double) -> Double? {
        guard let t = timer(m) else { return nil }
        if clock < t.first { return t.first }
        if t.every == 0 { return nil }
        return t.first + (floor((clock - t.first) / t.every) + 1) * t.every
    }
}

func mmss(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.down))
    return String(format: "%@%d:%02d", s < 0 ? "-" : "", abs(s) / 60, abs(s) % 60)
}

final class MatchState {
    private var matchID = ""
    private var roshanKilledAt: Double?
    private var aegisPickedAt: Double?
    private var aegisDeniedAt: Double?
    private var at10: (lh: Int, dn: Int, nw: Int)?
    private var previousClock: Double?
    private var endReported = ""

    /// Цена предмета по имени (blink, tpscroll…) — чтобы посчитать нетворс, если игра его не прислала.
    var itemCost: ((String) -> Int?)?
    var onMatchEnd: ((String) -> Void)?

    /// Возвращает nil, если матч сейчас не идёт.
    func ingest(_ json: [String: Any], turbo: Bool) -> Frame? {
        guard let map = json["map"] as? [String: Any], let clock = num(map["clock_time"]) else { return nil }
        let state = map["game_state"] as? String ?? ""
        let id = (map["matchid"] as? String) ?? ""

        if state == "DOTA_GAMERULES_STATE_POST_GAME" {
            if !id.isEmpty, id != "0", endReported != id { endReported = id; onMatchEnd?(id) }
            return nil
        }
        guard state == "DOTA_GAMERULES_STATE_PRE_GAME" || state == "DOTA_GAMERULES_STATE_GAME_IN_PROGRESS" else {
            return nil
        }

        if id != matchID {
            matchID = id
            roshanKilledAt = nil; aegisPickedAt = nil; aegisDeniedAt = nil
            at10 = nil; previousClock = nil
        }

        for event in (json["events"] as? [[String: Any]]) ?? [] {
            guard let t = num(event["game_time"]) else { continue }
            switch event["event_type"] as? String {
            case "roshan_killed": roshanKilledAt = max(roshanKilledAt ?? t, t)
            case "aegis_picked_up": aegisPickedAt = max(aegisPickedAt ?? t, t)
            case "aegis_denied": aegisDeniedAt = max(aegisDeniedAt ?? t, t)
            default: break
            }
        }

        var f = Frame()
        f.clock = clock
        f.matchID = id

        // Часы событий (game_time) переводим в часы матча (clock_time).
        if let gameTime = num(map["game_time"]) {
            let offset = gameTime - clock
            if let killed = roshanKilledAt {
                let r = Rules.roshan(turbo: turbo)
                let window = (from: killed - offset + r.min, to: killed - offset + r.max)
                if clock <= window.to { f.roshan = window }
            }
            if let picked = aegisPickedAt, !((aegisDeniedAt ?? -1) >= picked) {
                let until = picked - offset + Rules.aegis(turbo: turbo)
                if clock <= until { f.aegisUntil = until }
            }
        }

        let player = json["player"] as? [String: Any] ?? [:]
        if player["team2"] != nil || player["team3"] != nil {
            f.spectator = true
            f.teams = spectatorTeams(player: player, hero: json["hero"] as? [String: Any] ?? [:])
            return f
        }

        let hero = json["hero"] as? [String: Any] ?? [:]
        f.heroID = int(hero["id"])
        f.gold = int(player["gold"])
        f.gpm = int(player["gpm"])
        f.xpm = int(player["xpm"])
        f.kills = int(player["kills"])
        f.deaths = int(player["deaths"])
        f.assists = int(player["assists"])
        f.lastHits = int(player["last_hits"])
        f.denies = int(player["denies"])
        f.streak = int(player["kill_streak"])
        f.commands = int(player["commands_issued"])
        f.goldCreeps = int(player["gold_from_creep_kills"])
        f.goldHeroes = int(player["gold_from_hero_kills"])
        f.goldIncome = int(player["gold_from_income"])
        f.buybackCost = int(hero["buyback_cost"])
        f.buybackCooldown = num(hero["buyback_cooldown"])
        f.alive = hero["alive"] as? Bool
        f.respawn = num(hero["respawn_seconds"])
        f.wardCooldown = num(map["ward_purchase_cooldown"])

        if let radiant = int(map["radiant_score"]), let dire = int(map["dire_score"]),
           let team = player["team_name"] as? String {
            f.scoreOurs = team == "radiant" ? radiant : dire
            f.scoreTheirs = team == "radiant" ? dire : radiant
        }

        for (_, value) in (json["items"] as? [String: Any]) ?? [:] {
            if let name = (value as? [String: Any])?["name"] as? String, name.hasPrefix("item_") {
                f.items.insert(String(name.dropFirst(5)))
            }
        }

        if let nw = int(player["net_worth"]) {
            f.netWorth = nw
        } else if let gold = f.gold, let cost = itemCost, !f.items.isEmpty {
            f.netWorth = gold + f.items.reduce(0) { $0 + (cost($1) ?? 0) }
        } else {
            f.netWorth = f.gold
        }

        // Итог стадии линий снимаем в момент, когда часы переходят через 10:00.
        if at10 == nil, let before = previousClock, before < 600, clock >= 600,
           let lh = f.lastHits, let dn = f.denies, let nw = f.netWorth {
            at10 = (lh, dn, nw)
        }
        previousClock = clock
        f.at10 = at10
        return f
    }

    private func spectatorTeams(player: [String: Any], hero: [String: Any]) -> [TeamWorth] {
        var teams: [TeamWorth] = []
        for (key, title) in [("team2", tr("Свет", "Radiant")), ("team3", tr("Тьма", "Dire"))] {
            guard let players = player[key] as? [String: Any] else { continue }
            let heroes = hero[key] as? [String: Any] ?? [:]
            var rows: [(name: String, worth: Int)] = []
            for (slot, value) in players {
                guard let p = value as? [String: Any], let nw = int(p["net_worth"]) else { continue }
                let npc = (heroes[slot] as? [String: Any])?["name"] as? String ?? slot
                rows.append((npc, nw))
            }
            rows.sort { $0.worth > $1.worth }
            teams.append(TeamWorth(name: title, total: rows.reduce(0) { $0 + $1.worth }, heroes: rows))
        }
        return teams
    }

    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
}

/// Решает, какую подсказку показать и когда подать звук.
final class Alerts {
    private var fired: Set<String> = []
    private var matchID = ""
    var playSound: ((Metric) -> Void)?

    /// Возвращает текст подсказки (или nil). `watch` — события, за которыми следим.
    func update(_ f: Frame, settings s: Settings) -> String? {
        if f.matchID != matchID { matchID = f.matchID; fired = [] }
        guard !f.spectator else { return nil }

        var hint: String?
        func consider(_ m: Metric, key: String, text: String) {
            if hint == nil { hint = text }
            if fired.insert(key).inserted, s.sound, s.soundEvents.contains(m) { playSound?(m) }
        }
        let watch = s.shown.union(s.soundEvents)

        if let r = f.roshan, f.clock >= r.from, f.clock < r.to, watch.contains(.roshan) {
            consider(.roshan, key: "rosh@\(Int(r.from))", text: tr("Рошан может появиться", "Roshan may respawn"))
        }
        if let until = f.aegisUntil, until - f.clock > 0, until - f.clock <= 60, watch.contains(.aegis) {
            consider(.aegis, key: "aegis@\(Int(until))", text: tr("Эгида пропадёт через \(Int(until - f.clock)) с", "Aegis expires in \(Int(until - f.clock)) s"))
        }
        let order: [(Metric, String)] = [
            (.tormentor, tr("Терзатель", "Tormentor")), (.power, tr("Руны усиления", "Power runes")), (.wisdom, tr("Руны мудрости", "Wisdom runes")),
            (.bounty, tr("Руны богатства", "Bounty runes")), (.lotus, tr("Лотосы", "Lotus")), (.daynight, tr("Смена дня и ночи", "Day/night change")), (.stack, tr("Стак", "Stack")),
        ]
        for (m, title) in order where watch.contains(m) {
            guard let t = Rules.timer(m), let at = Rules.next(m, clock: f.clock) else { continue }
            let left = at - f.clock
            if left <= t.warn { consider(m, key: "\(m.rawValue)@\(Int(at))", text: tr("\(title) через \(Int(left.rounded(.up))) с", "\(title) in \(Int(left.rounded(.up))) s")) }
        }
        if hint == nil, f.clock >= Rules.buybackHintFrom(turbo: s.turbo), f.alive != false,
           let cost = f.buybackCost, let gold = f.gold, (f.buybackCooldown ?? 0) <= 0, gold < cost {
            hint = tr("Не хватает \(cost - gold) на выкуп", "\(cost - gold) short of buyback")
        }
        return s.shown.contains(.hints) ? hint : nil
    }
}

/// Пример для настройки окна: 19:15 матча, как в лаунчере.
func demoFrame(spectator: Bool = false) -> Frame {
    var f = Frame()
    f.clock = 19 * 60 + 15
    f.matchID = "demo"
    f.heroID = 84
    f.netWorth = 11870; f.gold = 1500; f.gpm = 586; f.xpm = 642
    f.kills = 5; f.deaths = 2; f.assists = 9
    f.lastHits = 136; f.denies = 8; f.streak = 3; f.commands = 4100
    f.goldCreeps = 5200; f.goldHeroes = 2600; f.goldIncome = 2900
    f.buybackCost = 1112; f.buybackCooldown = 0; f.alive = true
    f.scoreOurs = 21; f.scoreTheirs = 14
    f.wardCooldown = 0
    f.roshan = (23 * 60 + 10, 26 * 60 + 10)
    f.aegisUntil = 20 * 60 + 10
    f.at10 = (52, 6, 4310)
    f.items = ["arcane_boots", "hand_of_midas", "magic_wand"]
    return f
}
