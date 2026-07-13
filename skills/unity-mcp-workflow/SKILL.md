---
name: unity-mcp-workflow
description: "Drive the running Unity editor through a Unity MCP server — trigger asset refresh after C# edits, read the Console until clean, run EditMode/PlayMode tests via the editor's test runner, inspect scenes read-only — and decide between MCP (editor open) and the bundled headless scripts (editor closed). Use whenever Unity MCP tools are available in the session, or when a headless script refuses to run because `Temp/UnityLockfile` shows the editor has the project open."
---

# Unity MCP Workflow

Unity allows one editor instance per project, so the bundled headless scripts (`compile-check.sh`, `run-tests.sh`, `build-player.sh`) refuse to run while the user has the editor open. A Unity MCP server removes that limit: the agent verifies through the *running* editor instead. This skill decides which path to use and how to drive the MCP path safely. Pair with [[unity-conventions]] (compile check), [[unity-testing]] (headless runner), [[unity-build]] (clean-room ladder), and [[unity-yaml-assets]] (disk edits the editor must import).

## Detect first

- **MCP available?** Check the session's tool list for Unity MCP tools. Servers differ (CoplayDev unity-mcp, CoderGamester mcp-unity, others) — **discover the actual tool names and signatures; never assume them** from another server's API.
- **Editor open?** `Temp/UnityLockfile` present means the editor (or another batch process) has the project. After a crash the lockfile can be stale — if MCP calls fail and no Unity process is running, treat it as stale and use the headless path.

## Decision table

| State | Verification path |
| --- | --- |
| Editor open + MCP tools available | MCP: refresh → Console → tests |
| Editor open, no MCP | Ask the user to run the check in-editor or close it — **never kill the Unity process** to free the lock |
| Editor closed | Headless scripts ([[unity-conventions]] / [[unity-testing]] / [[unity-build]]) |
| Before a PR / release verdict | Always finish with a **clean-room headless run** (editor closed) — MCP verifies against the editor's live state, which can diverge from what's committed |

## The edit → verify loop over MCP

1. Edit C# (or YAML per [[unity-yaml-assets]]) on disk as usual.
2. **Trigger an asset refresh** via the MCP tool. Don't rely on the editor auto-refreshing on focus — the user may never focus it.
3. **Read the Console.** Fix `error CS*` first-error-first until the Console is clean. Compile warnings the project treats as errors count too.
4. **Run tests** through the editor's test-runner tool: the changed fixture filtered first (fast red-green), the full EditMode suite before declaring done — same discipline as [[unity-testing]], different transport.
5. Only after a clean Console + green tests, report the change as verified.

"No errors in my head" is not step 3. The Console is the ground truth while the editor is the compiler.

## Read vs mutate — the safety line

- **Freely:** read Console, scene hierarchy, component values, project/editor settings, play-mode state, run tests. Read operations are how MCP earns its keep.
- **Only when the task requires it:** creating/modifying scene objects, executing menu items, entering Play Mode. Prefer doing the change on disk and letting the refresh import it — the disk is what git sees.
- **Never silently:** save a scene or asset the user has open. The open scene may hold their **unsaved work**; a programmatic save commits state they haven't reviewed. If a mutation requires saving, say so and let the user decide.
- Mind the divergence both ways: your disk edits aren't live until refreshed; the user's unsaved editor state isn't on disk, so `git diff` doesn't see it.

## Play Mode via MCP

- Entering Play Mode with unsaved scene changes can lose them depending on editor settings — surface before entering.
- With domain reload disabled (Enter Play Mode Options), statics carry over between runs; a test that passes only on the first play smells of static state ([[unity-conventions]]).
- Always exit Play Mode when done; don't leave the user's editor running the game.

## Handoffs

- **Iteration:** editor open, MCP loop above.
- **Clean-room verification:** editor closed, `run-tests.sh` full suite, then the [[unity-build]] ladder for release-affecting changes. MCP results are a fast proxy, not the final gate — CI runs headless, so the headless run is what must be green.

## Anti-patterns

- Running `run-tests.sh` / `compile-check.sh` while `Temp/UnityLockfile` is present — guaranteed immediate failure.
- Killing the Unity process (or deleting a non-stale lockfile) to unblock a headless script.
- Calling MCP tools by names remembered from a different server instead of the session's actual tool list.
- Declaring a change done after "the file saved fine" without a refresh + Console read.
- Mutating or saving the user's open scene without being asked.
- Skipping the final headless run because "MCP tests were green" — editor-live state and committed state are not the same thing.

## Verification checklist

- [ ] Path chosen from the decision table (lockfile + MCP availability actually checked).
- [ ] Every disk edit was followed by an MCP asset refresh before reading results.
- [ ] Console read and clean (first error fixed first) before tests ran.
- [ ] Filtered tests during iteration, full EditMode suite before done.
- [ ] No scene/asset saved through MCP without explicit user intent.
- [ ] Release-affecting work finished with a clean-room headless run, editor closed.