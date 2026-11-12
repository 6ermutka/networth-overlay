// Содержимое окна поверх игры.

import SwiftUI

enum Palette {
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.35)
    static let dim = Color(white: 0.62)
    static let green = Color(red: 0.45, green: 0.9, blue: 0.5)
    static let red = Color(red: 1.0, green: 0.45, blue: 0.4)
}

struct Cell: Identifiable {
    let id: String
    let label: String
    let value: String
    var color: Color = .white
}

/// Строки окна: показатели и таймеры, которые выбраны и по которым есть данные.
func cells(for f: Frame, settings s: Settings, data: OpenData) -> [Cell] {
    let shown = s.shown
    var out: [Cell] = []
    func add(_ m: Metric, _ value: String?, _ color: Color = .white, label: String? = nil) {
        guard shown.contains(m), let value else { return }
        out.append(Cell(id: m.rawValue, label: label ?? m.title, value: value, color: color))
    }

    add(.gold, f.gold.map(String.init))

    if shown.contains(.buyback), let cost = f.buybackCost {
        if let cd = f.buybackCooldown, cd > 0 {
            add(.buyback, tr("\(cost) кд \(mmss(cd))", "\(cost) cd \(mmss(cd))"), Palette.red)
        } else if let gold = f.gold {
            add(.buyback, gold >= cost ? "\(cost) ✓" : "\(cost) −\(cost - gold)", gold >= cost ? Palette.green : Palette.red)
        }
    }
    if f.alive == false, let respawn = f.respawn, respawn > 0 {
        out.append(Cell(id: "respawn", label: tr("Возрождение", "Respawn"), value: mmss(respawn), color: Palette.red))
    }
    if let ours = f.scoreOurs, let theirs = f.scoreTheirs {
        add(.score, "\(ours) : \(theirs)", ours >= theirs ? Palette.green : Palette.red)
        if let k = f.kills, let a = f.assists, ours > 0 {
            add(.participation, "\(min(100, (k + a) * 100 / ours))%")
        }
    }
    if let streak = f.streak { add(.streak, "\(streak)", streak >= 3 ? Palette.gold : .white) }
    if let lh = f.lastHits, f.clock > 30 {
        add(.lhpm, String(format: "%.1f", Double(lh) / f.minutes))
    }
    if let t = f.at10 { add(.at10, "\(t.lh)/\(t.dn) · \(t.nw)") }
    if let commands = f.commands, f.clock > 30 { add(.apm, "\(Int(Double(commands) / f.minutes))") }
    if let creeps = f.goldCreeps, let heroes = f.goldHeroes, let income = f.goldIncome {
        let total = max(1, creeps + heroes + income)
        add(.sources, "\(creeps * 100 / total)/\(heroes * 100 / total)/\(income * 100 / total)%")
        add(.farm, "\(creeps)")
        add(.fromKills, "\(heroes)")
        add(.income, "\(income)")
    }
    if let median = data.median(f.heroID) {
        add(.heroGpm, "\(median.gpm)")
        add(.heroXpm, "\(median.xpm)")
    }
    if let ward = f.wardCooldown { add(.wards, ward <= 0 ? "✓" : mmss(ward), ward <= 0 ? Palette.green : .white) }

    for m in [Metric.power, .bounty, .wisdom, .lotus, .stack, .daynight, .tormentor] {
        guard let t = Rules.timer(m), let at = Rules.next(m, clock: f.clock) else { continue }
        let left = at - f.clock
        add(m, mmss(left), left <= t.warn ? Palette.gold : .white)
    }
    if let r = f.roshan {
        // Красный — ещё не может появиться, жёлтый — может.
        add(.roshan, "\(mmss(r.from))–\(mmss(r.to))", f.clock >= r.from ? Palette.gold : Palette.red)
    }
    if let until = f.aegisUntil {
        add(.aegis, mmss(until), until - f.clock <= 60 ? Palette.gold : .white)
    }
    return out
}

struct OverlayContent: View {
    let frame: Frame
    let settings: Settings
    let hint: String?
    let data: OpenData
    var revision = 0   // меняется, когда догрузились справочники или картинки

    private var k: CGFloat { CGFloat(settings.scale) }
    private func font(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size * k, weight: weight).monospacedDigit()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * k) {
            if frame.spectator { spectator } else { player }
        }
        .padding(.horizontal, 11 * k)
        .padding(.vertical, 8 * k)
        .background(
            RoundedRectangle(cornerRadius: 8 * k)
                .fill(Color(white: 0.05).opacity(0.9 * (1 - settings.opacity)))
        )
        .overlay(RoundedRectangle(cornerRadius: 8 * k).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .fixedSize()
    }

    @ViewBuilder private var player: some View {
        let shown = settings.shown
        let median = frame.clock >= 1200 ? data.median(frame.heroID) : nil

        HStack(alignment: .center, spacing: 8 * k) {
            if shown.contains(.hero), let portrait = data.heroImage(frame.heroID) {
                Image(nsImage: portrait).resizable().interpolation(.high)
                    .frame(width: 39 * k, height: 22 * k)
                    .clipShape(RoundedRectangle(cornerRadius: 3 * k))
            }
            if shown.contains(.nw), let nw = frame.netWorth {
                HStack(alignment: .firstTextBaseline, spacing: 5 * k) {
                    Circle().fill(Palette.gold).frame(width: 9 * k, height: 9 * k)
                    Text(String(nw)).font(font(19, .bold)).foregroundColor(Palette.gold)
                }
            }
            if shown.contains(.gpm), let gpm = frame.gpm {
                rate("\(gpm) GPM", value: gpm, median: median?.gpm)
            }
            if shown.contains(.xpm), let xpm = frame.xpm {
                rate("\(xpm) XPM", value: xpm, median: median?.xpm)
            }
        }

        if settings.detailed {
            let rows = cells(for: frame, settings: settings, data: data)
            if !rows.isEmpty {
                if settings.column { column(rows) } else { grid(rows) }
            }
            let heroName = shown.contains(.hero) && data.hasHero(frame.heroID) ? frame.heroID.map(data.heroName) : nil
            if shown.contains(.build), let build = data.build(heroID: frame.heroID, clock: frame.clock, owned: frame.items) {
                buildLine(build, heroName: heroName)
            } else if let heroName {
                Text(heroName).font(font(10)).foregroundColor(Palette.dim)
            }
            if let hint {
                Text(hint).font(font(11, .semibold)).foregroundColor(Palette.gold)
            }
        }
    }

    private func rate(_ text: String, value: Int, median: Int?) -> some View {
        HStack(spacing: 2 * k) {
            Text(text).font(font(11)).foregroundColor(Palette.dim)
            if let median {
                Text(value >= median ? "▲" : "▼").font(font(8))
                    .foregroundColor(value >= median ? Palette.green : Palette.red)
            }
        }
    }

    private func column(_ rows: [Cell]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12 * k, verticalSpacing: 2 * k) {
            ForEach(rows) { cell in
                GridRow {
                    Text(cell.label).font(font(11)).foregroundColor(Palette.dim)
                    Text(cell.value).font(font(12, .bold)).foregroundColor(cell.color)
                }
            }
        }
    }

    private func grid(_ rows: [Cell]) -> some View {
        let pairs = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0..<min($0 + 2, rows.count)]) }
        return Grid(alignment: .leading, horizontalSpacing: 8 * k, verticalSpacing: 2 * k) {
            ForEach(pairs.indices, id: \.self) { i in
                GridRow {
                    ForEach(pairs[i]) { cell in
                        Text(cell.label).font(font(11)).foregroundColor(Palette.dim)
                        Text(cell.value).font(font(12, .bold)).foregroundColor(cell.color)
                            .padding(.trailing, 6 * k)
                    }
                }
            }
        }
    }

    /// Сборка: иконки предметов в ряд, под каждой цена; купленное приглушено и отмечено ✓.
    private func buildLine(_ build: (phase: String, items: [OpenData.Item]), heroName: String?) -> some View {
        VStack(alignment: .leading, spacing: 3 * k) {
            Text((heroName.map { $0 + " · " } ?? "") + build.phase).font(font(10)).foregroundColor(Palette.dim)
            HStack(alignment: .top, spacing: 5 * k) {
                ForEach(build.items, id: \.key) { item in
                    let owned = frame.items.contains(item.key)
                    VStack(spacing: 1 * k) {
                        ZStack(alignment: .bottomTrailing) {
                            if let icon = data.image(item.img) {
                                Image(nsImage: icon).resizable().interpolation(.high)
                                    .frame(width: 33 * k, height: 24 * k)
                                    .clipShape(RoundedRectangle(cornerRadius: 3 * k))
                                    .opacity(owned ? 0.45 : 1)
                            } else {
                                // Картинка ещё не скачалась — короткое название.
                                Text(item.name).font(font(8)).foregroundColor(.white)
                                    .multilineTextAlignment(.center).lineLimit(2)
                                    .frame(width: 33 * k, height: 24 * k)
                                    .background(RoundedRectangle(cornerRadius: 3 * k).fill(Color.white.opacity(0.08)))
                            }
                            if owned {
                                Text("✓").font(font(13, .heavy)).foregroundColor(Palette.green)
                                    .shadow(color: .black, radius: 1.5)
                                    .padding(.trailing, 2 * k)
                            }
                        }
                        Text(item.cost > 0 ? String(item.cost) : " ").font(font(9))
                            .foregroundColor(owned ? Palette.green : Palette.dim)
                    }
                }
            }
        }
    }

    @ViewBuilder private var spectator: some View {
        if frame.teams.count == 2 {
            let diff = frame.teams[0].total - frame.teams[1].total
            HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                Text(tr("Свет ", "Radiant ") + String(frame.teams[0].total)).font(font(13, .bold)).foregroundColor(Palette.green)
                Text(tr("Тьма ", "Dire ") + String(frame.teams[1].total)).font(font(13, .bold)).foregroundColor(Palette.red)
                Text((diff >= 0 ? "+" : "−") + String(abs(diff))).font(font(12, .bold)).foregroundColor(Palette.gold)
            }
        }
        if settings.detailed {
            HStack(alignment: .top, spacing: 14 * k) {
                ForEach(frame.teams.indices, id: \.self) { t in
                    Grid(alignment: .leading, horizontalSpacing: 8 * k, verticalSpacing: 1 * k) {
                        ForEach(frame.teams[t].heroes.indices, id: \.self) { i in
                            let hero = frame.teams[t].heroes[i]
                            GridRow {
                                Text(data.heroName(npc: hero.name)).font(font(11)).foregroundColor(Palette.dim)
                                Text(String(hero.worth)).font(font(11, .bold)).foregroundColor(.white)
                            }
                        }
                    }
                }
            }
        }
    }
}
