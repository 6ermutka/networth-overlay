cask "networth-overlay" do
  version "1.0.1"
  sha256 "7de63b074e2245b0331efdc227020ba1e62e54f53a45c90a9beb55636167640e"

  url "https://github.com/6ermutka/networth-overlay/releases/download/v#{version}/NetworthOverlay-#{version}.zip"
  name "Networth Overlay"
  desc "Net worth and timers overlay for Dota 2 via official Game State Integration"
  homepage "https://github.com/6ermutka/networth-overlay"

  depends_on macos: :ventura

  app "Networth Overlay.app"

  # Приложение подписано без сертификата разработчика Apple (ad-hoc), поэтому снимаем
  # карантин, иначе macOS не даст его открыть.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/Networth Overlay.app"],
        must_succeed: false
  end

  uninstall quit: "local.networth-overlay"

  zap trash: [
    "~/Library/Application Support/NetworthOverlay",
    "~/Library/Preferences/local.networth-overlay.plist",
  ]
end
