cask "clipshelf" do
  version :latest
  sha256 :no_check

  url "https://github.com/shiaho777/clipshelf/releases/latest/download/ClipShelf-#{version}.dmg"
  name "ClipShelf"
  desc "macOS menu bar clipboard history with rules and app-aware paste"
  homepage "https://github.com/shiaho777/clipshelf"

  depends_on macos: ">= :ventura"

  app "ClipShelf.app"

  zap trash: [
    "~/Library/Application Support/ClipShelf",
    "~/Library/Preferences/com.nicebro.ClipShelf.plist",
    "~/Library/Caches/com.nicebro.ClipShelf",
  ]
end
