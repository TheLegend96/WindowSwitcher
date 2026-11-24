cask "window-switcher" do
  version "1.0.0"
  sha256 "6ec066e93201999f8a4f1c18b82266c20a818947ee4ee52627987e108271d60b"

  url "https://github.com/TheLegend96/WindowSwitcher/releases/download/v#{version}/WindowSwitcher.dmg"
  name "Window Switcher"
  desc "Fast, elegant individual window switcher for macOS"
  homepage "https://github.com/TheLegend96/WindowSwitcher"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "WindowSwitcher.app"

  uninstall quit: "com.custom.windowswitcher"

  zap trash: [
    "~/Library/Preferences/com.custom.windowswitcher.plist",
  ]
end
