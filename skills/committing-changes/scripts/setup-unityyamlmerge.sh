#!/bin/bash
# Configure Unity SmartMerge (UnityYAMLMerge) as this repo's git mergetool,
# so scene/prefab/asset YAML conflicts resolve semantically via `git mergetool`.
# Run from the Unity project root (reads ProjectSettings/ProjectVersion.txt).
# UNITYYAMLMERGE_PATH overrides tool auto-discovery. Idempotent.

set -u
PROJECT="$(pwd)"

if [[ ! -f "$PROJECT/ProjectSettings/ProjectVersion.txt" ]]; then
    echo "ERROR: no ProjectSettings/ProjectVersion.txt — run from the Unity project root." >&2
    exit 1
fi

VERSION="$(grep -m1 'm_EditorVersion:' "$PROJECT/ProjectSettings/ProjectVersion.txt" | awk '{print $2}')"

TOOL="${UNITYYAMLMERGE_PATH:-}"
if [[ -z "$TOOL" ]]; then
    for c in \
        "C:/Program Files/Unity/Hub/Editor/$VERSION/Editor/Data/Tools/UnityYAMLMerge.exe" \
        "/Applications/Unity/Hub/Editor/$VERSION/Unity.app/Contents/Tools/UnityYAMLMerge" \
        "$HOME/Unity/Hub/Editor/$VERSION/Editor/Data/Tools/UnityYAMLMerge"; do
        if [[ -f "$c" ]]; then TOOL="$c"; break; fi
    done
fi

if [[ -z "$TOOL" || ! -f "$TOOL" ]]; then
    echo "ERROR: UnityYAMLMerge for Unity $VERSION not found in Hub default paths." >&2
    echo "Set UNITYYAMLMERGE_PATH to the tool binary and retry." >&2
    exit 1
fi

# Official Unity SmartMerge mergetool config (per-repo)
git config merge.tool unityyamlmerge
git config mergetool.unityyamlmerge.trustExitCode false
git config mergetool.unityyamlmerge.cmd "\"$TOOL\" merge -p \"\$BASE\" \"\$REMOTE\" \"\$LOCAL\" \"\$MERGED\""

echo "Configured Unity SmartMerge for this repo:"
echo "  tool: $TOOL"
echo "On a conflicted merge, run: git mergetool"
echo "Note: the path is pinned to Unity $VERSION — re-run this script after an editor upgrade."
