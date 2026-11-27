cask "window-switcher" do
  version "1.0.0"
  sha256 "e17fc272157b6b4c00511e324578913d74cf0dc0c80ba7dfd9b428fe3a7fcd12"

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
