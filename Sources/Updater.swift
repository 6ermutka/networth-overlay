// Обновления: сверяем версию с последним релизом на GitHub и ставим новую через Homebrew.
// Адрес репозитория вшивается при сборке (ключ NWORepository в Info.plist, берётся из файла REPO).

import AppKit

final class Updater {
    static let cask = "networth-overlay"

    let repo = Bundle.main.object(forInfoDictionaryKey: "NWORepository") as? String ?? ""
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    var configured: Bool { !repo.isEmpty }
    var releasesURL: URL? { URL(string: "https://github.com/\(repo)/releases/latest") }

    var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Приложение поставлено через Homebrew — значит, им же можно обновлять.
    var installedViaBrew: Bool {
        guard brew != nil else { return false }
        return ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains {
            FileManager.default.fileExists(atPath: $0 + "/" + Updater.cask)
        }
    }

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

    /// Запускает `brew upgrade` отдельным процессом, который переживёт выход приложения,
    /// и снова открывает приложение. Журнал — ~/Library/Logs/NetworthOverlay-update.log.
    func installWithBrew() -> Bool {
        guard let brew, installedViaBrew else { return false }
        let log = NSHomeDirectory() + "/Library/Logs/NetworthOverlay-update.log"
        let script = """
        sleep 2
        { date; "$BREW" update; "$BREW" upgrade --cask \(Updater.cask); } >> "$LOG" 2>&1
        open "/Applications/Networth Overlay.app"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var env = ProcessInfo.processInfo.environment
        env["BREW"] = brew
        env["LOG"] = log
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // обновляем явно, строкой выше
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
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
