#!/bin/zsh
# Builds Magpie.app into ./build.
#
#   ./build.sh             release build only
#   ./build.sh --install   also copy to /Applications and launch (quits the running copy first)
#   ./build.sh --debug     debug build (combine with --install if you like)
#
# Environment:
#   VERSION         overrides CFBundleShortVersionString (e.g. 0.2.0)
#   BUILD_NUMBER    CFBundleVersion (default: the number of commits)
#   SIGN_IDENTITY   codesigning identity (default: your Apple Development certificate when
#                   you have one, otherwise "-" for ad hoc, which is fine for your own Mac)
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

swift build -c $config 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$(swift build -c $config --show-bin-path)/$name"
[[ -x $bin ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find Sources -name '*.swift' -newer "$bin" | head -1)
if [[ -n $stale ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config 2>&1 | grep -E "error" | head -20
  exit 1
fi

app=build/$name.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp "$bin" $app/Contents/MacOS/
cp Resources/Info.plist $app/Contents/
cp -X Resources/Assets.car Resources/AppIcon.icns $app/Contents/Resources/

if [[ -n ${VERSION:-} ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" $app/Contents/Info.plist
fi
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" $app/Contents/Info.plist

identity=${SIGN_IDENTITY:-}
if [[ -z $identity ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n $identity ]] || identity=-
xattr -cr $app
codesign --force --sign "$identity" $app 2>&1 | grep -v "replacing existing signature" || true
echo "built $app (signed: $identity)"

if [[ " $* " == *" --install "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/$name.app
  ditto $app /Applications/$name.app
  echo "installed /Applications/$name.app"
  open /Applications/$name.app
fi
