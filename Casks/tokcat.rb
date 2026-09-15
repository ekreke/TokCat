cask "tokcat" do
  version "0.1.1"
  sha256 "23207bcc306500aa8938eeadaa2a689c9025651e82e93483756fe5adfc528614"

  url "https://github.com/ekreke/TokCat/releases/download/v#{version}/TokCat-#{version}.dmg"
  name "TokCat"
  desc "Menu bar cat that runs at your AI token consumption rate"
  homepage "https://github.com/ekreke/TokCat"

  depends_on macos: :ventura

  app "TokCat.app"

  zap trash: "~/Library/Preferences/com.ekreke.tokcat.plist"
end
