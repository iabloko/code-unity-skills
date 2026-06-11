# code-unity-skills

Unity-focused skills for [Claude Code](https://claude.com/claude-code): conventions, architecture, testing, performance, and the surrounding engineering discipline. Distributed as the `unity-skills` plugin via this repo's own marketplace.

## Install

```
/plugin marketplace add iabloko/code-unity-skills
/plugin install unity-skills@iabloko
```

## What's inside

### Unity skills

| Skill | Covers |
| --- | --- |
| `unity-conventions` | C# naming, MonoBehaviour lifecycle, serialization, assembly definitions, UniTask/TMP defaults |
| `unity-architecture` | Clean Architecture, DI (Zenject/VContainer), State Machine, Orchestrator |
| `unity-testing` | Unity Test Framework — EditMode-first TDD, PlayMode when lifecycle is under test |
| `unity-unitask` | UniTask as the default async primitive — cancellation, PlayerLoop timing, coroutine migration |
| `unity-ui` | uGUI + TMP — canvas rebuild cost, raycast hygiene, passive View + Presenter, list pooling |
| `unity-performance` | Profiler-first workflow, GC allocations, pooling, draw calls, URP |
| `unity-editor-scripting` | Custom inspectors, EditorWindow, PropertyDrawer — Odin Inspector first when present |
| `unity-addressables` | Runtime asset loading via Addressables instead of `Resources.Load` |
| `unity-dotween` | DOTween Pro tweens, sequences, UniTask integration |
| `unity-unirx` | UniRx reactive streams — only when the project already depends on it |

### Engineering skills

`engineering-philosophy`, `shell-discipline`, `committing-changes` (feature branch + PR + git hooks), `running-tdd-cycles`, `reviewing-changes` (five-pass review), `designing-architecture`.

### CLAUDE.md template

[`CLAUDE.md`](CLAUDE.md) is a behavioral-guidelines template to merge into your Unity project's own instructions. The slash commands it mentions (`/coding-skills:*`) come from the separate `coding-skills` plugin.

## License

[MIT](LICENSE)