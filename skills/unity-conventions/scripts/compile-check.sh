#!/bin/bash
# Compile the Unity project headless and report C# compiler errors.
# Fastest feedback loop: no tests, just a script-compilation + import pass.
# Side effect: imports new assets and generates their .meta files.
# Usage (from the Unity project root): compile-check.sh
# UNITY_PATH overrides editor auto-discovery (Hub default install paths).
# Exit codes: 0 = compiles clean, 1 = compile errors or run error.

set -u
PROJECT="$(pwd)"

if [[ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]]; then
    echo "ERROR: no ProjectSettings/ProjectVersion.txt — run from the Unity project root." >&2
    exit 1
fi

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

mkdir -p "$PROJECT/Logs"
LOG="$PROJECT/Logs/compile-check-$(date +%Y%m%d-%H%M%S).log"

echo "Unity $VERSION → compile check"
"$UNITY" -batchmode -nographics -quit -projectPath "$PROJECT" -logFile "$LOG"
CODE=$?

# -quit can return 0 even when scripts fail to compile — the log is the truth
if grep -q 'error CS' "$LOG"; then
    echo "Compile FAILED:"
    grep 'error CS' "$LOG" | sort -u | head -30
    exit 1
fi

if [[ $CODE -ne 0 ]]; then
    echo "ERROR: Unity exited with $CODE (no compile errors in log — inspect $LOG)." >&2
    tail -20 "$LOG" >&2
    exit 1
fi

echo "Compile OK."
