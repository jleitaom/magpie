#!/bin/zsh
# Builds Magpie.app into ./build.
#
#   ./build.sh             release build only
#   ./build.sh --install   also copy to /Applications and launch (quits the running copy first)
#   ./build.sh --debug     debug build (combine with --install if you like)
#
# Environment:
#   VERSION         overrides CFBundleShortVersionString (e.g. 1.0.0). Set for releases
#                   (scripts/package.sh), which also builds for both Apple silicon and Intel.
#   BUILD_NUMBER    CFBundleVersion (default: the number of commits, so it grows with every
#                   release; macOS and update checks compare this one)
#   SIGN_IDENTITY   codesigning identity (default: "Magpie Self-Signed" when it's in your
#                   keychain, so rebuilds keep Safari and Screen Recording access; otherwise
#                   "-" for ad hoc, which is fine for your own Mac)
set -euo pipefail
cd "${0:A:h}"
name=Magpie
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
car=Resources/Assets.car
if [[ ! -f $car || -n "$(find Icon/AppIcon.icon -newer $car | head -1)" ]]; then
  scripts/make-icon.sh
fi

flags=(-c $config)
[[ -n ${VERSION:-} ]] && flags+=(--arch arm64 --arch x86_64)
swift build $flags 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
binDir="$(swift build $flags --show-bin-path)"
bin="$binDir/$name"
[[ -x $bin ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find Sources -name '*.swift' -newer "$bin" | head -1)
if [[ -n $stale ]]; then
  echo "build failed: binary is older than $stale"
  swift build $flags 2>&1 | grep -E "error" | head -20
  exit 1
fi

app=build/$name.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources $app/Contents/Frameworks
cp "$bin" $app/Contents/MacOS/
ditto "$binDir/Sparkle.framework" $app/Contents/Frameworks/Sparkle.framework
# Sparkle's XPC services are only needed by sandboxed apps, and Magpie isn't sandboxed.
rm -rf $app/Contents/Frameworks/Sparkle.framework/{Versions/B/XPCServices,XPCServices}
cp Resources/Info.plist $app/Contents/
cp -X Resources/Assets.car Resources/AppIcon.icns $app/Contents/Resources/

if [[ -n ${VERSION:-} ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" $app/Contents/Info.plist
fi
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" $app/Contents/Info.plist

identity=${SIGN_IDENTITY:-}
if [[ -z $identity ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Magpie Self-Signed"'; then
  identity="Magpie Self-Signed"
fi
[[ -n $identity ]] || identity=-
xattr -cr $app
# Sign from the inside out with the same identity, so Sparkle's helpers and the app match.
sparkle=$app/Contents/Frameworks/Sparkle.framework
for part in $sparkle/Versions/B/Autoupdate $sparkle/Versions/B/Updater.app $sparkle; do
  codesign --force --options runtime --timestamp=none --sign "$identity" $part 2>&1 | grep -v "replacing existing signature" || true
done
codesign --force --options runtime --timestamp=none --entitlements Resources/Magpie.entitlements \
  --sign "$identity" $app 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --strict $app || { echo "signature check failed"; exit 1; }
echo "built $app (signed: $identity)"

if [[ " $* " == *" --install "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/$name.app
  ditto $app /Applications/$name.app
  echo "installed /Applications/$name.app"
  open /Applications/$name.app
fi
