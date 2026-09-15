cask "tokcat" do
  version "0.1.9"
  sha256 "5c7401cc37cfb96158b1d8fd0dc47ec2afe63314024968180646d03c626bf470"

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
