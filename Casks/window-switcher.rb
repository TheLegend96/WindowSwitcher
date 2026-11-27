cask "window-switcher" do
  version "1.0.0"
  sha256 "f1bfa6d58cf6b76d9364388e0be11367440dcd282b529f0211db241bb645401c"

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
