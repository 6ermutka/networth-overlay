#!/bin/zsh
# Выпускает релиз: собирает приложение, пакует в zip, обновляет cask, коммитит, ставит тег
# и публикует релиз на GitHub. Перед запуском поднимите номер в файле VERSION.
# Нужны: gh (вход выполнен) и чистое рабочее дерево.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
REPO="$(tr -d '[:space:]' < REPO)"
TAG="v$VERSION"
ZIP="build/NetworthOverlay-$VERSION.zip"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Тег $TAG уже есть — поднимите номер в VERSION." >&2; exit 1
fi
if [[ -n "$(git status --porcelain -- . ':!VERSION')" ]]; then
  echo "Есть незакоммиченные изменения — сначала закоммитьте их." >&2; exit 1
fi

./build.sh
rm -f "$ZIP"
ditto -c -k --keepParent "build/Networth Overlay.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

cat > Casks/networth-overlay.rb <<CASK
cask "networth-overlay" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/NetworthOverlay-#{version}.zip"
  name "Networth Overlay"
  desc "Net worth and timers overlay for Dota 2 via official Game State Integration"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :ventura"

  app "Networth Overlay.app"

  # Приложение подписано без сертификата разработчика Apple (ad-hoc), поэтому снимаем
  # карантин, иначе macOS не даст его открыть.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Networth Overlay.app"]
  end

  uninstall quit: "local.networth-overlay"

  zap trash: [
    "~/Library/Application Support/NetworthOverlay",
    "~/Library/Preferences/local.networth-overlay.plist",
  ]
end
CASK

git add VERSION Casks/networth-overlay.rb
git commit -m "Release $TAG"
git tag "$TAG"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Networth Overlay $VERSION" --generate-notes
echo "Релиз $TAG опубликован: https://github.com/$REPO/releases/tag/$TAG"
