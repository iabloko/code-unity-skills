#!/bin/bash
# Verify .meta pairing under Assets/: every asset file and folder needs
# <name>.meta, and every .meta needs its asset. Honors .gitignore
# (untracked-but-ignored paths are skipped, matching what gets committed).
# Skips paths Unity itself ignores (components starting with '.' or ending '~').
# Usage: check-meta.sh [unity-project-root]   (default: current directory)
# Exit: 0 = clean, 1 = violations, 2 = not a Unity project.

set -u
cd "${1:-.}" || exit 2

if [[ ! -d Assets ]]; then
    echo "ERROR: no Assets/ directory here — run from the Unity project root." >&2
    exit 2
fi

PROBLEMS="$(git ls-files --cached --others --exclude-standard -- Assets | awk '
    function visible(p,  n, parts, i) {
        n = split(p, parts, "/")
        for (i = 1; i <= n; i++)
            if (parts[i] ~ /^\./ || parts[i] ~ /~$/) return 0
        return 1
    }
    visible($0) {
        all[$0] = 1
        if ($0 ~ /\.meta$/) metas[$0] = 1
        else assets[$0] = 1
        # every ancestor folder below Assets/ is itself an asset needing a .meta
        p = $0
        while (match(p, /\/[^\/]*$/)) {
            p = substr(p, 1, RSTART - 1)
            if (p == "Assets") break
            dirs[p] = 1
        }
    }
    END {
        for (a in assets) if (!((a ".meta") in all)) print "MISSING " a ".meta"
        for (d in dirs)   if (!((d ".meta") in all)) print "MISSING " d ".meta"
        for (m in metas) {
            base = substr(m, 1, length(m) - 5)
            # base may legitimately be on disk but invisible to git (ignored,
            # e.g. generated assets) — fall back to a filesystem check
            if (!(base in assets) && !(base in dirs) && system("test -e \"" base "\"") != 0)
                print "ORPHAN  " m
        }
    }' | sort)"

if [[ -n "$PROBLEMS" ]]; then
    echo "$PROBLEMS"
    echo ""
    echo "ERROR: $(echo "$PROBLEMS" | wc -l | tr -d ' ') .meta violation(s)." >&2
    echo "MISSING → commit the .meta with its asset (open the editor or run a batchmode command to generate it)." >&2
    echo "ORPHAN  → the asset is gone; delete the leftover .meta in the same change." >&2
    exit 1
fi

echo ".meta check passed."