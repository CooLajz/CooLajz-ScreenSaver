#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./script/build_and_run.sh --build
INSTALL_DIR="${1:-/Applications}"
APP_NAME='CooLajz ScreenSaver.app'
mkdir -p "$INSTALL_DIR"
if [[ -e "$INSTALL_DIR/$APP_NAME" ]]; then
    BACKUP_DIR="$(mktemp -d /private/tmp/atlas-installed-backup.XXXXXX)"
    ditto "$INSTALL_DIR/$APP_NAME" "$BACKUP_DIR/$APP_NAME"
    echo "Předchozí aplikace je zálohovaná v $BACKUP_DIR."
    pkill -x CooLajzScreenSaver >/dev/null 2>&1 || true
    rm -rf "$INSTALL_DIR/$APP_NAME"
else
    pkill -x CooLajzScreenSaver >/dev/null 2>&1 || true
fi
ditto --norsrc --noextattr "dist/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
codesign --verify --deep --strict "$INSTALL_DIR/$APP_NAME"
open -n "$INSTALL_DIR/$APP_NAME"
echo "Atlas je nainstalovaný v $INSTALL_DIR/$APP_NAME."
