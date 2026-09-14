cask "tokcat" do
  version "0.1.0"
  sha256 "4e631b23327b62c7380095b754e95a40cc6e0cd4a4df02651660d382b7942887"

  url "https://github.com/ekreke/TokCat/releases/download/v#{version}/TokCat-#{version}.dmg",
      verified: "github.com/ekreke/TokCat/"
  name "TokCat"
  desc "Menu bar cat that runs at your AI token consumption rate"
  homepage "https://github.com/ekreke/TokCat"

  depends_on macos: :ventura

  app "TokCat.app"

  zap trash: "~/Library/Preferences/com.ekreke.tokcat.plist"
end
