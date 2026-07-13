cask "clipboardmanager" do
  version :latest
  sha256 :no_check

  url "https://github.com/nicebro/ClipboardManager/releases/latest/download/ClipboardManager-#{version}.dmg"
  name "ClipboardManager"
  desc "Lightweight macOS clipboard manager with fuzzy search and smart paste"
  homepage "https://github.com/nicebro/ClipboardManager"

  depends_on macos: ">= :ventura"

  app "ClipboardManager.app"

  zap trash: [
    "~/Library/Application Support/ClipboardManager",
    "~/Library/Preferences/com.nicebro.ClipboardManager.plist",
    "~/Library/Caches/com.nicebro.ClipboardManager",
  ]
end
