// Открытые данные OpenDota (api.opendota.com): названия и цены предметов, имена героев,
// типичные GPM/XPM героя, популярные предметы и итоги матча. Ключ не нужен.
// В запросах уходит только номер героя или матча.
// Картинки предметов и героев — с CDN Steam (cdn.cloudflare.steamstatic.com), кэшируются на диске.

import AppKit

struct MatchPlayer: Identifiable {
    let id: Int
    let hero: String
    let heroID: Int
    let radiant: Bool
    let kills: Int, deaths: Int, assists: Int
    let netWorth: Int, gold: Int, gpm: Int, xpm: Int, lastHits: Int, denies: Int
}

struct MatchSummary {
    let id: String
    let radiantWin: Bool
    let duration: Int
    let radiantScore: Int
    let direScore: Int
    let players: [MatchPlayer]
}

final class OpenData {
    struct Item { let key: String; let name: String; let cost: Int; let img: String? }

    static var phases: [String] { [tr("Стартовый закуп", "Starting items"), tr("Ранняя игра", "Early game"), tr("Середина", "Mid game"), tr("Поздняя игра", "Late game")] }

    var enabled = true
    var onUpdate: (() -> Void)?

    private var itemsByID: [Int: Item] = [:]
    private var itemsByKey: [String: Item] = [:]
    private var heroNames: [Int: String] = [:]
    private var heroByNpc: [String: String] = [:]
    private var heroImages: [Int: String] = [:]
    private var images: [String: NSImage] = [:]
    private var imageRequests: Set<String> = []
    private var medians: [Int: (gpm: Int, xpm: Int)] = [:]
    private var builds: [Int: [[Int]]] = [:]
    private var requested: Set<String> = []

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NetworthOverlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: Что знаем

    func cost(ofItem key: String) -> Int? { itemsByKey[key]?.cost }
    func heroName(_ id: Int) -> String { heroNames[id] ?? tr("Герой \(id)", "Hero \(id)") }
    func heroName(npc: String) -> String {
        heroByNpc[npc] ?? npc.replacingOccurrences(of: "npc_dota_hero_", with: "")
    }
    func median(_ heroID: Int?) -> (gpm: Int, xpm: Int)? { heroID.flatMap { medians[$0] } }

    static let buildSize = 6

    /// Популярные предметы героя для текущей стадии матча — всегда до шести штук.
    /// Стадия идёт по часам (стартовый закуп — до 2:00, ранняя игра — до 12:00, середина — до 25:00),
    /// но переключается раньше, если всё из текущей уже куплено.
    func build(heroID: Int?, clock: Double, owned: Set<String>) -> (phase: String, items: [Item])? {
        guard let heroID, let phases = builds[heroID] else { return nil }
        func own(_ index: Int) -> [Item] { phases[index].compactMap { itemsByID[$0] } }

        var index = clock < 120 ? 0 : clock < 720 ? 1 : clock < 1500 ? 2 : 3
        while index < 3 {
            let top = own(index).prefix(OpenData.buildSize)
            guard !top.isEmpty, top.allSatisfy({ owned.contains($0.key) }) else { break }
            index += 1
        }

        // Если в статистике для стадии меньше шести предметов, добираем из следующих стадий,
        // а на последней — из предыдущих.
        var items: [Item] = []
        for source in [index] + Array((index + 1)..<4) + (0..<index).reversed() {
            for item in own(source) where items.count < OpenData.buildSize {
                if !items.contains(where: { $0.key == item.key }) { items.append(item) }
            }
        }
        return items.isEmpty ? nil : (OpenData.phases[index], items)
    }

    func hasHero(_ id: Int?) -> Bool { id.map { heroNames[$0] != nil } ?? false }
    func heroImage(_ id: Int?) -> NSImage? { image(id.flatMap { heroImages[$0] }) }

    /// Картинка по пути из справочника OpenDota. Пока не скачана — nil; после загрузки зовёт onUpdate.
    func image(_ path: String?) -> NSImage? {
        guard let path, let clean = path.split(separator: "?").first.map(String.init) else { return nil }
        if let ready = images[clean] { return ready }
        let file = cacheDir.appendingPathComponent("img" + clean.replacingOccurrences(of: "/", with: "_"))
        if let cached = NSImage(contentsOf: file) {
            images[clean] = cached
            return cached
        }
        guard enabled, clean.hasPrefix("/apps/dota2/images/"), imageRequests.insert(clean).inserted,
              let url = URL(string: "https://cdn.cloudflare.steamstatic.com" + clean) else { return nil }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let image = NSImage(data: data) else { return }
            try? data.write(to: file, options: .atomic)
            DispatchQueue.main.async {
                self?.images[clean] = image
                self?.onUpdate?()
            }
        }.resume()
        return nil
    }

    // MARK: Загрузка

    func loadConstants() {
        constant("items") { [weak self] json in
            guard let self, let dict = json as? [String: Any] else { return }
            for (key, value) in dict {
                guard let v = value as? [String: Any], let id = (v["id"] as? NSNumber)?.intValue else { continue }
                let item = Item(key: key, name: v["dname"] as? String ?? key, cost: (v["cost"] as? NSNumber)?.intValue ?? 0,
                                img: v["img"] as? String)
                self.itemsByID[id] = item
                self.itemsByKey[key] = item
            }
            self.onUpdate?()
        }
        constant("heroes") { [weak self] json in
            guard let self, let dict = json as? [String: Any] else { return }
            for (_, value) in dict {
                guard let v = value as? [String: Any], let id = (v["id"] as? NSNumber)?.intValue,
                      let name = v["localized_name"] as? String else { continue }
                self.heroNames[id] = name
                if let npc = v["name"] as? String { self.heroByNpc[npc] = name }
                if let img = v["img"] as? String { self.heroImages[id] = img }
            }
            self.onUpdate?()
        }
    }

    /// Подгружает данные героя один раз за запуск.
    func prepare(heroID: Int?) {
        guard enabled, let heroID, requested.insert("hero\(heroID)").inserted else { return }
        fetch("benchmarks?hero_id=\(heroID)") { [weak self] json in
            guard let result = (json as? [String: Any])?["result"] as? [String: Any] else { return }
            func median(_ key: String) -> Int? {
                for row in (result[key] as? [[String: Any]]) ?? [] {
                    if let p = (row["percentile"] as? NSNumber)?.doubleValue, abs(p - 0.5) < 0.01 {
                        return (row["value"] as? NSNumber)?.intValue
                    }
                }
                return nil
            }
            if let gpm = median("gold_per_min"), let xpm = median("xp_per_min") {
                self?.medians[heroID] = (gpm, xpm)
                self?.onUpdate?()
            }
        }
        fetch("heroes/\(heroID)/itemPopularity") { [weak self] json in
            guard let dict = json as? [String: Any] else { return }
            let keys = ["start_game_items", "early_game_items", "mid_game_items", "late_game_items"]
            self?.builds[heroID] = keys.map { key in
                let counts = dict[key] as? [String: Any] ?? [:]
                return counts
                    .compactMap { id, n in Int(id).map { ($0, (n as? NSNumber)?.intValue ?? 0) } }
                    .sorted { $0.1 > $1.1 }
                    .map { $0.0 }
            }
            self?.onUpdate?()
        }
    }

    func fetchMatch(_ id: String, completion: @escaping (MatchSummary?) -> Void) {
        guard enabled else { completion(nil); return }
        fetch("matches/\(id)") { [weak self] json in
            guard let self, let d = json as? [String: Any], let rows = d["players"] as? [[String: Any]], !rows.isEmpty else {
                completion(nil); return
            }
            func n(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
            let players = rows.enumerated().map { index, p in
                MatchPlayer(id: index, hero: self.heroName(n(p["hero_id"])), heroID: n(p["hero_id"]),
                            radiant: (p["isRadiant"] as? Bool) ?? (n(p["player_slot"]) < 128),
                            kills: n(p["kills"]), deaths: n(p["deaths"]), assists: n(p["assists"]),
                            netWorth: n(p["net_worth"]), gold: n(p["total_gold"]), gpm: n(p["gold_per_min"]),
                            xpm: n(p["xp_per_min"]), lastHits: n(p["last_hits"]), denies: n(p["denies"]))
            }
            completion(MatchSummary(id: id, radiantWin: (d["radiant_win"] as? Bool) ?? false, duration: n(d["duration"]),
                                    radiantScore: n(d["radiant_score"]), direScore: n(d["dire_score"]), players: players))
        }
    }

    /// Справочник: берём с диска, если ему меньше недели, иначе качаем и кладём в кэш.
    private func constant(_ name: String, use: @escaping (Any) -> Void) {
        let file = cacheDir.appendingPathComponent("\(name).json")
        let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            .map { Date().timeIntervalSince($0) }
        if let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) {
            use(json)
            if let age, age < 7 * 86400 { return }
        }
        guard enabled else { return }
        request("constants/\(name)") { data in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) else { return }
            try? data.write(to: file, options: .atomic)
            use(json)
        }
    }

    private func fetch(_ path: String, use: @escaping (Any?) -> Void) {
        request(path) { data in use(data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) }
    }

    private func request(_ path: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "https://api.opendota.com/api/" + path) else { completion(nil); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("NetworthOverlay/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ProcessInfo.processInfo.environment["NWO_DEBUG"] != nil {
                FileHandle.standardError.write(Data("\(path): \((response as? HTTPURLResponse)?.statusCode ?? -1) \(data?.count ?? 0) bytes \(error?.localizedDescription ?? "")\n".utf8))
            }
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }
}
