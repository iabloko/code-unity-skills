# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## 5. Active Skills

### Unity skills (auto-activated when relevant)

| Skill | When it applies |
| --- | --- |
| `unity-conventions` | Any C# file in a Unity project — naming, MonoBehaviour, serialization, UniTask, TMP, DOTween defaults |
| `unity-architecture` | Designing or wiring a feature — DI (Zenject/VContainer), layering, State Machine, Orchestrator |
| `unity-testing` | Any logic change — EditMode TDD first, PlayMode only when lifecycle is under test |
| `unity-unitask` | Any async code — UniTask signatures, cancellation, PlayerLoop timing; replaces coroutines/Task |
| `unity-ui` | Any Canvas/uGUI work — rebuild cost, raycast hygiene, passive View + Presenter, TMP |
| `unity-performance` | Any per-frame path or mobile/VR target — measure first, then fix GC/pooling/draw calls |
| `unity-editor-scripting` | Editor tools, custom inspectors, PropertyDrawer — Odin first if present |
| `unity-dotween` | Any value animating over time — DOTween Pro is the default tween engine |
| `unity-unirx` | Reactive state binding or streams — only when UniRx is confirmed in `manifest.json` |
| `unity-addressables` | Any runtime asset load — replaces `Resources.Load` and bare `[SerializeField]` prefab refs |
| `unity-build` | Release-affecting changes — headless player build, Addressables content, IL2CPP/stripping |

### Engineering skills (auto-activated when relevant; the principles apply to every code change)

- `engineering-philosophy` — KISS, YAGNI, DRY, SOLID on every code decision.
- `shell-discipline` — safe shell usage (PowerShell or bash): one command per call, no inline env vars.
- `committing-changes` — no direct pushes to `main`, always feature branch + PR.
- `running-tdd-cycles` — red→green→refactor discipline on every logic change.
- `reviewing-changes` — five-pass review (code, security, architecture, acceptance, AI-native).
- `designing-architecture` — requirements + library scan before implementing any new system.

### Slash commands

These commands are provided by the separate `coding-skills` plugin, not by `unity-skills`. They work only if that plugin is also installed; the underlying skills above ship with this plugin either way.

| Command | When to use |
| --- | --- |
| `/coding-skills:tdd` | Writing or fixing C# game logic — red-green-refactor |
| `/coding-skills:design` | Before implementing a new game system |
| `/coding-skills:review` | Before merging any branch — five-pass quality gate |
| `/coding-skills:commit` | Creating commits and PRs |
| `/coding-skills:pm` | Planning features via GitHub Issues |
