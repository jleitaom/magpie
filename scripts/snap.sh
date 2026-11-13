#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: scripts/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings scripts/snap.sh
#        APP_SNAPSHOT_SIZE=1500x885 APP_SNAPSHOT_PAGES=all scripts/snap.sh   (a window of that size, in points)
set -u
app=${0:A:h:h}/build/Magpie.app/Contents/MacOS/Magpie
store=/tmp/Magpie-test.store
shots=/tmp/Magpie-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.jleitaom.magpie.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
