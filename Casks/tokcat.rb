cask "tokcat" do
  version "0.1.6"
  sha256 "7f04bc1e66e0e81a882a669cf22b9e3126288ecedb7b2c0056ce17eb7680843a"

  url "https://github.com/ekreke/TokCat/releases/download/v#{version}/TokCat-#{version}.dmg"
  name "TokCat"
  desc "Menu bar cat that runs at your AI token consumption rate"
  homepage "https://github.com/ekreke/TokCat"

  depends_on macos: :ventura

  app "TokCat.app"

  caveats <<~EOS
    TokCat 是菜单栏应用（运行时不显示 Dock 图标）。
    安装后在「启动台 / 应用程序」或 Spotlight 中打开即可。
  EOS

  zap trash: "~/Library/Preferences/com.ekreke.tokcat.plist"
end
