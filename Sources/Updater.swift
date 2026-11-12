// Обновления: сверяем версию с последним релизом на GitHub и ставим новую через Homebrew.
// Адрес репозитория вшивается при сборке (ключ NWORepository в Info.plist, берётся из файла REPO).

import AppKit

final class Updater {
    static let cask = "networth-overlay"

    let repo = Bundle.main.object(forInfoDictionaryKey: "NWORepository") as? String ?? ""
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var configured: Bool { !repo.isEmpty }
    var releasesURL: URL? { URL(string: "https://github.com/\(repo)/releases/latest") }

    /// Homebrew, которым поставлено приложение. На одном Mac их бывает два (/opt/homebrew и /usr/local),
    /// и cask с доверенным tap есть только в одном — поэтому ищем тот, в чьём Caskroom лежит наш cask.
    var brew: String? {
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let binary = prefix + "/bin/brew"
            if FileManager.default.isExecutableFile(atPath: binary),
               FileManager.default.fileExists(atPath: prefix + "/Caskroom/" + Updater.cask) {
                return binary
            }
        }
        return nil
    }

    /// Приложение поставлено через Homebrew — значит, им же можно обновлять.
    var installedViaBrew: Bool { brew != nil }

    let logPath = NSHomeDirectory() + "/Library/Logs/NetworthOverlay-update.log"
    private let statusPath = NSTemporaryDirectory() + "networth-overlay-update.status"

    /// Этап идущего обновления: fetch → install → restart, либо fail. nil — обновление не идёт.
    var stage: String? {
        (try? String(contentsOfFile: statusPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearStage() { try? FileManager.default.removeItem(atPath: statusPath) }

    /// Отдаёт номер более новой версии или nil, если обновлений нет (или узнать не удалось).
    func check(completion: @escaping (_ newer: String?, _ failed: Bool) -> Void) {
        guard configured, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            completion(nil, true); return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("NetworthOverlay/\(current)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [current] data, response, _ in
            var latest: String?
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            }
            DispatchQueue.main.async {
                guard let latest else { completion(nil, true); return }
                completion(Updater.isNewer(latest, than: current) ? latest : nil, false)
            }
        }.resume()
    }

    /// Запускает обновление отдельным процессом, который переживёт выход приложения: подтягивает tap,
    /// делает `brew upgrade`, проверяет, что версия действительно сменилась, и перезапускает приложение.
    /// Этапы пишет в файл состояния (см. `stage`), подробности — в журнал `logPath`.
    func installWithBrew(target: String) -> Bool {
        guard let brew, configured else { return false }
        let script = """
        echo fetch > "$STATUS"
        echo "=== $(date) обновление до $TARGET через $BREW" >> "$LOG"
        TAP="$("$BREW" --repo "$TAPNAME" 2>/dev/null)"
        # Быстрый путь: обновить только наш tap; если не вышло — обычный brew update.
        if ! { [ -d "$TAP/.git" ] && git -C "$TAP" pull --ff-only -q >> "$LOG" 2>&1; }; then
          "$BREW" update >> "$LOG" 2>&1
        fi
        echo install > "$STATUS"
        HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" upgrade --cask "$TAPNAME/\(Updater.cask)" >> "$LOG" 2>&1
        NOW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
        if [ "$NOW" = "$TARGET" ]; then
          echo restart > "$STATUS"
          sleep 1
          pkill -x NetworthOverlay
          sleep 1
          rm -f "$STATUS"
          open "$APP"
        else
          echo "=== не обновилось: установлена $NOW, ожидалась $TARGET" >> "$LOG"
          echo fail > "$STATUS"
          pgrep -x NetworthOverlay > /dev/null || open "$APP"
        fi
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var env = ProcessInfo.processInfo.environment
        env["BREW"] = brew
        env["LOG"] = logPath
        env["STATUS"] = statusPath
        env["TARGET"] = target
        env["TAPNAME"] = repo
        env["APP"] = "/Applications/Networth Overlay.app"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? "fetch".write(toFile: statusPath, atomically: true, encoding: .utf8)
        return (try? process.run()) != nil
    }

    /// Сравнение версий по числам: 1.10.0 новее, чем 1.9.3.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
