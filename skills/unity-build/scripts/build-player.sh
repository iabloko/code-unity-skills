#!/bin/bash
# Build a standalone desktop player headless.
# Usage (from the Unity project root):
#   build-player.sh [Win64|OSXUniversal|Linux64] [output-path]
# Defaults: host platform; output under Builds/<target>/.
# Android/iOS and Addressables content builds need an -executeMethod entry
# point — see the unity-build SKILL.md.
# UNITY_PATH overrides editor auto-discovery.
# Exit codes: 0 = build succeeded, anything else = failure (see log).

set -u
PROJECT="$(pwd)"

if [[ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]]; then
    echo "ERROR: no ProjectSettings/ProjectVersion.txt — run from the Unity project root." >&2
    exit 1
fi

case "$(uname -s)" in
    Darwin) HOST_TARGET="OSXUniversal" ;;
    Linux)  HOST_TARGET="Linux64" ;;
    *)      HOST_TARGET="Win64" ;;
esac
TARGET="${1:-$HOST_TARGET}"

case "$TARGET" in
    Win64)        BUILD_FLAG="-buildWindows64Player"; DEFAULT_OUT="Builds/Win64/Player.exe" ;;
    OSXUniversal) BUILD_FLAG="-buildOSXUniversalPlayer"; DEFAULT_OUT="Builds/OSX/Player.app" ;;
    Linux64)      BUILD_FLAG="-buildLinux64Player"; DEFAULT_OUT="Builds/Linux64/Player.x86_64" ;;
    *)
        echo "ERROR: unsupported target '$TARGET' (use Win64, OSXUniversal, or Linux64)." >&2
        echo "Android/iOS builds need an -executeMethod entry point — see the unity-build skill." >&2
        exit 1
        ;;
esac
OUT="${2:-$PROJECT/$DEFAULT_OUT}"

VERSION="$(grep -m1 'm_EditorVersion:' "$PROJECT/ProjectSettings/ProjectVersion.txt" | awk '{print $2}')"

UNITY="${UNITY_PATH:-}"
if [[ -z "$UNITY" ]]; then
    for c in \
        "C:/Program Files/Unity/Hub/Editor/$VERSION/Editor/Unity.exe" \
        "/Applications/Unity/Hub/Editor/$VERSION/Unity.app/Contents/MacOS/Unity" \
        "$HOME/Unity/Hub/Editor/$VERSION/Editor/Unity"; do
        if [[ -f "$c" ]]; then UNITY="$c"; break; fi
    done
fi

if [[ -z "$UNITY" || ! -f "$UNITY" ]]; then
    echo "ERROR: Unity $VERSION not found in Unity Hub default paths." >&2
    echo "Set UNITY_PATH to the editor binary and retry." >&2
    exit 1
fi

if [[ -f "$PROJECT/Temp/UnityLockfile" ]]; then
    echo "ERROR: Temp/UnityLockfile exists — the project is open in another Unity instance." >&2
    echo "Close the editor (or delete the stale lockfile after a crash) and retry." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")" "$PROJECT/Logs"
LOG="$PROJECT/Logs/build-$TARGET-$(date +%Y%m%d-%H%M%S).log"

echo "Unity $VERSION → $TARGET player build"
echo "  output: $OUT"
"$UNITY" -batchmode -nographics -quit -projectPath "$PROJECT" \
    -buildTarget "$TARGET" "$BUILD_FLAG" "$OUT" -logFile "$LOG"
CODE=$?

if grep -q 'error CS' "$LOG"; then
    echo "Build FAILED — compile errors:"
    grep 'error CS' "$LOG" | sort -u | head -30
    exit 1
fi

if [[ $CODE -ne 0 ]]; then
    echo "Build FAILED (Unity exit $CODE). Last log lines:" >&2
    tail -30 "$LOG" >&2
    exit $CODE
fi

echo "Build OK → $OUT"
