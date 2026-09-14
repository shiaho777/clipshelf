cask "clipshelf" do
  version "1.2.2"
  sha256 "aea1b0c8e1b5217665bc61ba5af9e31223789e18c1a58f5c6bc03ae24f5d5b6d"

  url "https://github.com/shiaho777/clipshelf/releases/download/v#{version}/ClipShelf-#{version}.dmg"
  name "ClipShelf"
  desc "macOS menu bar clipboard history with rules and app-aware paste"
  homepage "https://github.com/shiaho777/clipshelf"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "ClipShelf.app"

  zap trash: [
    "~/Library/Application Support/ClipShelf",
    "~/Library/Preferences/com.nicebro.ClipShelf.plist",
    "~/Library/Caches/com.nicebro.ClipShelf",
    "~/Library/LaunchAgents/com.nicebro.ClipShelf.plist",
    "~/Library/Saved Application State/com.nicebro.ClipShelf.savedState",
  ]
end
