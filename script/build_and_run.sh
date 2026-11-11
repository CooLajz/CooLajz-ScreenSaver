#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build|--verify|--debug|--logs|--telemetry|--check|--lighting-check|--timing-check|--geometry-gallery|--morph-preview) ;; *) echo 'Použití: script/build_and_run.sh [--build|--verify|--debug|--logs|--telemetry|--check|--lighting-check|--timing-check|--geometry-gallery|--morph-preview]' >&2; exit 2;; esac
case "$MODE" in --build|--check|--lighting-check|--timing-check|--geometry-gallery|--morph-preview) ;; *) pkill -x CooLajzScreenSaver >/dev/null 2>&1 || true;; esac
mkdir -p .build dist
xcodebuild -project CooLajzScreenSaver.xcodeproj -scheme CooLajzScreenSaver -configuration Release \
    -derivedDataPath "$ROOT_DIR/.build" -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build > .build/build.log 2>&1 || {
    rg -n -C 3 'error:' .build/build.log || true
    tail -25 .build/build.log; exit 1;
}
STAGING_DIR="$(mktemp -d /private/tmp/coolajz-screensaver.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT
for NAME in 'CooLajz ScreenSaver.app' 'Atlas.saver'; do
    # Documents can regain FinderInfo while Finder/LaunchServices inspects an
    # open app. Sign outside File Provider storage, then copy the sealed bundle.
    ditto --norsrc --noextattr ".build/Build/Products/Release/$NAME" "$STAGING_DIR/$NAME"
    xattr -cr "$STAGING_DIR/$NAME"
    if [[ "$NAME" == *.app ]]; then
        codesign --force --sign - --timestamp=none --entitlements Resources/Extension.entitlements "$STAGING_DIR/$NAME/Contents/PlugIns/AtlasExtension.appex"
        codesign --force --sign - --timestamp=none "$STAGING_DIR/$NAME/Contents/Resources/Atlas.saver"
    fi
    codesign --force --sign - --timestamp=none "$STAGING_DIR/$NAME"
    codesign --verify --deep --strict "$STAGING_DIR/$NAME"
    ditto -c -k --norsrc --noextattr --keepParent "$STAGING_DIR/$NAME" "dist/$NAME.zip"
    rm -rf "dist/$NAME"
    ditto --norsrc --noextattr "$STAGING_DIR/$NAME" "dist/$NAME"
    xattr -dr com.apple.FinderInfo "dist/$NAME" 2>/dev/null || true
    xattr -dr com.apple.ResourceFork "dist/$NAME" 2>/dev/null || true
done
APP="$ROOT_DIR/dist/CooLajz ScreenSaver.app"
BINARY="$APP/Contents/MacOS/CooLajzScreenSaver"
case "$MODE" in
    --build) echo 'Aplikace a spořič jsou sestavené ve složce dist/.' ;;
    --check) "$BINARY" --render-check "$ROOT_DIR/.build/checks" ;;
    --lighting-check) "$BINARY" --lighting-check "$ROOT_DIR/.build/lighting-checks" ;;
    --timing-check) "$BINARY" --timing-check ;;
    --geometry-gallery) "$BINARY" --geometry-gallery "$ROOT_DIR/.build/morph-gallery" ;;
    --morph-preview) "$BINARY" --morph-preview "$ROOT_DIR/.build/morph-preview" ;;
    --debug) lldb -- "$BINARY" ;;
    --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "CooLajzScreenSaver"' ;;
    --verify) open -n "$APP"; sleep 2; pgrep -x CooLajzScreenSaver >/dev/null; echo 'Aplikace běží.' ;;
    run) open -n "$APP" ;;
esac
