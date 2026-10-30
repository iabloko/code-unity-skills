#!/bin/bash
# PostToolUse hook: lint the C# lines the agent just added against unity-skills rules.
# Reads the tool payload from stdin, lints only lines added since HEAD (so
# pre-existing code never nags), and on violations exits 2 so the findings are
# fed straight back to the agent as blocking feedback.
#
# Scope: .cs files inside a Unity project (ProjectSettings/ProjectVersion.txt).

set -u

MARKER='NO''COMMIT'   # split so this script never matches its own gate

payload="$(cat)"

file_path="$(printf '%s' "$payload" | tr -d '\n' | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$file_path" ] || exit 0
file_path="$(printf '%s' "$file_path" | sed 's/\\\\/\//g; s/\\/\//g')"

case "$file_path" in *.cs) ;; *) exit 0 ;; esac
[ -f "ProjectSettings/ProjectVersion.txt" ] || exit 0
[ -f "$file_path" ] || exit 0

if git rev-parse --verify HEAD >/dev/null 2>&1 && git ls-files --error-unmatch "$file_path" >/dev/null 2>&1; then
    added="$(git diff HEAD -- "$file_path" | grep -E '^\+[^+]' | cut -c2-)"
else
    added="$(cat "$file_path")"
fi
[ -n "$added" ] || exit 0

FINDINGS=""

flag () {
    local pattern="$1" msg="$2" hits
    hits="$(printf '%s\n' "$added" | grep -E "$pattern" | grep -v "$MARKER" | head -n 3)"
    if [ -n "$hits" ]; then
        FINDINGS="${FINDINGS}
✗ ${msg}
$(printf '%s\n' "$hits" | sed 's/^/    > /')"
    fi
}

flag '(^[[:space:]]*|[;}][[:space:]]*)(//|/\*)' \
    "Comments are forbidden (unity-conventions): rename/extract until the code reads on its own. Only exception: a '// ${MARKER}' marker on a temporary hack."
flag 'Resources\.Load' \
    "Resources.Load is forbidden (unity-addressables): use Addressables or a serialized reference."
flag 'async[[:space:]]+void' \
    "async void is forbidden (unity-unitask): use async UniTaskVoid + .Forget(); Inspector-wired UnityEvent handlers are the only exception."
flag '\.GetAwaiter\(\)\.GetResult\(\)|\.Wait\(\)' \
    "Blocking waits deadlock under Unity's sync context (unity-unitask): redesign the caller as async."
flag '(^|[^[:alnum:]_.])(FindObjectOfType|FindFirstObjectByType|FindAnyObjectByType|GameObject\.Find\(|SendMessage\()' \
    "Find*/SendMessage are forbidden in shipping code (unity-conventions): inject via DI or a serialized reference."
flag 'UnityEngine\.UI\.Text' \
    "Legacy UI.Text is forbidden (unity-ui): use TMP_Text / TextMeshProUGUI."

if [ -d "Assets/Plugins/Sirenix" ] || grep -qi 'sirenix' Packages/manifest.json 2>/dev/null; then
    flag '\[(Header|Space)\(' \
        "[Header]/[Space] are forbidden when Odin is present (unity-editor-scripting): use [Title]/[BoxGroup]/[PropertySpace]."
fi

if grep -q 'com\.unity\.inputsystem' Packages/manifest.json 2>/dev/null; then
    flag '(^|[^[:alnum:]_.])Input\.(GetKey|GetAxis|GetButton|GetMouseButton|anyKey|mousePosition)' \
        "Legacy Input.* alongside the new Input System (unity-input): use the .inputactions wrapper / IInputSource."
fi

if [ -n "$FINDINGS" ]; then
    {
        echo "unity-skills lint — the lines you just added to $file_path violate skill rules. Fix them now; load the named skill for the full rule."
        printf '%s\n' "$FINDINGS"
        echo ""
        echo "Lines carrying '${MARKER}' are exempt here, but the pre-commit hook blocks committing them — use '// ${MARKER}' only for temporary hacks the user asked for."
    } >&2
    exit 2
fi

exit 0