#!/bin/bash
# Prints the Homebrew cask for one release, for jleitaom/homebrew-tap (Casks/magpie.rb).
#
#   scripts/cask.sh <version> <sha256 of Magpie-<version>.zip>
set -euo pipefail

VERSION=${1:?usage: scripts/cask.sh <version> <sha256>}
SHA256=${2:?sha256}

cat <<EOF2
cask "magpie" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/jleitaom/magpie/releases/download/v#{version}/Magpie-#{version}.zip"
  name "Magpie"
  desc "Save links, images, videos and notes, and actually come back to them"
  homepage "https://github.com/jleitaom/magpie"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Magpie updates itself with Sparkle.
  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Magpie.app"

  uninstall quit: "com.jleitaom.magpie"

  # Only with --zap: this also deletes your library.
  zap trash: [
    "~/Library/Application Support/Magpie",
    "~/Library/Caches/com.jleitaom.magpie",
    "~/Library/HTTPStorages/com.jleitaom.magpie",
    "~/Library/Preferences/com.jleitaom.magpie.plist",
  ]
end
EOF2
