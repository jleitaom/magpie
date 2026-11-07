#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.jleitaom.magpie.savedState
store=/tmp/Magpie-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ${0:A:h:h}/build/Magpie.app/Contents/MacOS/Magpie --selftest
