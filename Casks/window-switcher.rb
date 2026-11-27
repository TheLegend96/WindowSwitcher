cask "window-switcher" do
  version "1.0.0"
  sha256 "8378578a421418a56e722e9c1131973f908ea2a38cb3bcc0598771c5d8186a8f"

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
