#!/bin/bash
# Run Unity Test Framework tests headless (batchmode CLI).
# Usage (from the Unity project root):
#   run-tests.sh [EditMode|PlayMode] [testFilter]
# UNITY_PATH overrides editor auto-discovery (Hub default install paths).
# Exit codes: 0 = all passed, 2 = test failures, anything else = run error.

set -u

PLATFORM="${1:-EditMode}"
FILTER="${2:-}"
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

# Unity allows one instance per project; a present lockfile means the editor
# (or another batch run) has it open — or crashed and left a stale lock.
if [[ -f "$PROJECT/Temp/UnityLockfile" ]]; then
    echo "ERROR: Temp/UnityLockfile exists — the project is open in another Unity instance." >&2
    echo "Close the editor (or delete the stale lockfile after a crash) and retry." >&2
    exit 1
fi

mkdir -p "$PROJECT/TestResults"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS="$PROJECT/TestResults/$PLATFORM-$STAMP.xml"
LOG="$PROJECT/TestResults/$PLATFORM-$STAMP.log"

ARGS=(-batchmode -nographics -projectPath "$PROJECT" -runTests
      -testPlatform "$PLATFORM" -testResults "$RESULTS" -logFile "$LOG")
if [[ -n "$FILTER" ]]; then ARGS+=(-testFilter "$FILTER"); fi

echo "Unity $VERSION → $PLATFORM tests${FILTER:+ (filter: $FILTER)}"
echo "  results: $RESULTS"
"$UNITY" "${ARGS[@]}"
CODE=$?

attr() { grep -m1 -o '<test-run[^>]*' "$RESULTS" | sed -n "s/.*$1=\"\([^\"]*\)\".*/\1/p"; }

if [[ -f "$RESULTS" ]]; then
    echo "Result: $(attr result) — total $(attr total), passed $(attr passed), failed $(attr failed), skipped $(attr skipped)"
    grep -o '<test-case[^>]*result="Failed"' "$RESULTS" \
        | sed -n 's/.*fullname="\([^"]*\)".*/  FAILED: \1/p'
else
    echo "ERROR: no results XML produced — the run aborted before tests (exit $CODE)." >&2
    echo "Compile errors, if any:" >&2
    grep -m10 'error CS' "$LOG" >&2 || tail -20 "$LOG" >&2
fi

exit $CODE