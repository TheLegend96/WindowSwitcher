cask "window-switcher" do
  version "1.0.0"
  sha256 "8905c1612fa2b58811e6be52d818b7c8ffb3f5e41cae9d98a5fbc601d0bab892"

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
