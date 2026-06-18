---
name: unity-conventions
description: Apply Unity C# conventions — MonoBehaviour lifecycle, ScriptableObject configs, serialization, namespaces, assembly definitions. Use whenever editing or creating C# files inside a Unity project (presence of `Assets/`, `ProjectSettings/`, or `Packages/manifest.json`).
---

# Unity C# Conventions

Applies to any C# code inside a Unity project. Pair with `unity-architecture` for DI/patterns and `unity-editor-scripting` for editor-side code.

## Detect first

Before writing code, run these checks once per session and cache the result:

- `Packages/manifest.json` → identify Unity version constraints and which third-party packages are present (Zenject, VContainer, Odin, UniTask, R3, etc.).
- `Assets/**/*.asmdef` → know the assembly boundaries; new scripts must land in an assembly that already references the types they use.
- `ProjectSettings/ProjectVersion.txt` → Unity editor version — this caps the C# language version (see table below).
- Render pipeline: look for `UniversalRenderPipelineAsset` or `HDRenderPipelineAsset` assets, or the `com.unity.render-pipelines.universal` package.

If any of these are missing, ask before assuming.

## C# language version ceiling

Unity's compiler is pinned per editor version — write to the ceiling, not to the latest C# you know:

| Unity version | C# | Not available (do not write) |
| --- | --- | --- |
| 2020.3 LTS | 8.0 | records, `init`, target-typed `new`, pattern-matching relational/`and`/`or` |
| 2021.2 – 2022.3 LTS | 9.0 | file-scoped namespaces, global usings (C# 10); `required`, raw strings (C# 11); primary constructors, collection expressions `[..]` (C# 12) |
| Unity 6 (6000.x) | 9.0 | same ceiling — Unity has not moved past C# 9 |

Even within C# 9, **covariant return types and module initializers don't work** — they need runtime support Unity's profile lacks. When unsure whether a feature exists in the project's ceiling, the fast check is `compile-check.sh` (below).

## Naming

- Types, methods, properties: `PascalCase`.
- Private fields: `_camelCase` (leading underscore).
- Serialized private fields: `_camelCase` with `[SerializeField]` — never make a field `public` just to expose it in the Inspector.
- Constants: `PascalCase` (not `SCREAMING_CASE`).
- Booleans: prefix with `is/has/can/should` (`_isReady`, `HasTarget`).
- Async methods returning `Task`/`UniTask`: suffix `Async`.

## Comments

**Do not write comments — neither XML doc (`///` / `/** */`) nor inline (`//` / `/* */`).** Code must read on its own: express intent through precise names, small methods, and well-named types. A comment that feels necessary is a signal to rename or extract a method instead, not to annotate.

- This includes `///` `<summary>` blocks on public members — omit them.
- When editing existing code, do not add comments; you may leave pre-existing ones untouched (removing them is a separate, unrequested change — see Surgical Changes).
- Not comments, so allowed: `#region`, `#pragma`, `#if` directives, and attribute usage. Add `// TODO` / `// HACK` only when the user explicitly asks for them.

## File / assembly layout

- One public type per file; file name = type name.
- Group code into `*.asmdef`-bounded assemblies by feature, not by layer. Domain code must not reference `UnityEngine.UI` or `UnityEditor`.
- Editor-only code lives under an `Editor/` folder with an editor-only `*.asmdef` (`includePlatforms: ["Editor"]`).
- Tests live under `Tests/Editor` and `Tests/Runtime` with their own `*.asmdef` referencing `UnityEngine.TestRunner` and `UnityEditor.TestRunner`.

## `.meta` hygiene

Every file and folder under `Assets/` has a paired `.meta` holding its GUID; all asset references resolve by GUID. Agents editing the project outside the Unity editor are the main source of `.meta` drift.

- Commit an asset and its `.meta` **together** — including the `.meta` of every new folder on the path.
- Deleting or renaming an asset deletes/renames its `.meta` in the same change. A leftover `.meta` is an orphan; a missing one regenerates with a **new GUID** on next editor open, silently breaking every reference to the old one.
- Never hand-edit or regenerate the GUID of an existing `.meta`; never copy a `.meta` between assets (duplicate GUIDs).
- Files created outside the editor have no `.meta` yet — generate it by opening the editor or running any batchmode command (a headless test run per [[unity-testing]] does it), then commit the pair.

Per-commit gating is already handled: the `committing-changes` pre-commit hook (installed by its `install-hooks.sh`) checks staged `.meta` pairing on every commit. The bundled checker is the **full-tree audit** — run it on demand or in CI (`<skills>` = this plugin's `skills/` directory — the folder that holds this skill's own folder; `./skills/` in the source repo):

```sh
bash <skills>/unity-conventions/scripts/check-meta.sh    # from the Unity project root
```

It flags `MISSING` (asset without `.meta`) and `ORPHAN` (`.meta` without asset), honors `.gitignore`, and skips paths Unity itself ignores (dot-prefixed, `~`-suffixed).

## Compile check (headless)

The fastest feedback loop after editing C# — no tests, just a script-compilation pass:

```sh
bash <skills>/unity-conventions/scripts/compile-check.sh    # from the Unity project root
```

Locates the editor the same way as `run-tests.sh` (`ProjectVersion.txt` + Hub paths, `UNITY_PATH` override), refuses to run while the editor has the project open, and prints deduplicated `error CS*` lines on failure. Exit `0` = compiles clean. Side effect: imports new assets and generates their `.meta` files — run it after creating files outside the editor, then commit the asset+`.meta` pairs. Use it between edits; escalate to the full test run ([[unity-testing]]) before declaring a change done.

## MonoBehaviour

- Cache component references in `Awake` / `OnEnable`; never call `GetComponent` in `Update`.
- Use `[RequireComponent(typeof(T))]` to make dependencies explicit instead of `GetComponent` in `Start`.
- Prefer `OnEnable`/`OnDisable` for event subscription — they pair correctly with domain-reload toggles and pooling.
- Don't put logic in constructors — Unity may not have initialized the object yet. Use `Awake`.
- Avoid `FindObjectOfType`, `GameObject.Find`, `SendMessage`, `BroadcastMessage` in shipping code. They are slow and fragile; use DI or explicit references.
- `Update`/`FixedUpdate`/`LateUpdate` methods should be tiny dispatchers — extract logic into plain C# classes that are unit-testable without a scene.

## Serialization & configuration

- Configuration data → `ScriptableObject` (one asset per config, referenced via `[SerializeField]`). Do **not** hard-code tunables in MonoBehaviours.
- Prefer `[SerializeField] private T _field;` over `public T field;`.
- For data classes that need to be serialized but aren't `UnityEngine.Object`, mark them `[Serializable]`.
- Use `[field: SerializeField]` for auto-property backing fields when an immutable public surface is wanted.
- **When Odin is present, never use `[Header]` for inspector layout** — use Odin grouping/labelling instead (`[Title]`, `[BoxGroup]`, `[FoldoutGroup]`, `[PropertySpace]`, `[LabelText]`). The same goes for `[Space]`/`[Tooltip]` layout — prefer the Odin equivalents. `[Header]` is acceptable only when Odin is absent. See [[unity-editor-scripting]].

## Coroutines vs async (default: UniTask)

**UniTask is the default in this user's projects.** Assume `com.cysharp.unitask` is present; if it isn't in `manifest.json`, ask before falling back to coroutines.

- Use `UniTask` / `UniTaskVoid` over `IEnumerator` coroutines and over `Task` for any Unity-thread work. Coroutines are reserved for `WaitForEndOfFrame`-style cases that don't have a UniTask equivalent.
- Always accept a `CancellationToken`. Tie MonoBehaviour-owned work to `destroyCancellationToken` (Unity ≥ 2022.2) or `this.GetCancellationTokenOnDestroy()` (UniTask helper).
- Use `UniTask.WhenAll` / `UniTask.WhenAny` instead of manual flag juggling.
- For fire-and-forget on a Unity event, declare `async UniTaskVoid` and call with `.Forget()` — surfaces unhandled exceptions; never use `async void` (except for `UnityEvent`-bound handlers that the inspector wires up).
- Avoid `.GetAwaiter().GetResult()` and `.Task.Wait()` — deadlocks under Unity's sync context.
- See [[unity-unitask]] for full rules (cancellation ownership, PlayerLoop timing, coroutine migration).

## Text (default: TextMeshPro)

**TMP is the default for text.** Assume `com.unity.textmeshpro` (or the modern `com.unity.ugui` TMP integration) is present.

- Use `TMP_Text` / `TextMeshProUGUI` — never `UnityEngine.UI.Text` in new code.
- Update text via `SetText(StringBuilder)` or `SetText(string)` — avoid string concatenation in `Update` (see [[unity-performance]]).
- TMP font assets are `ScriptableObject`s; treat them as content (good candidates for [[unity-addressables]]).
- `TMP_InputField` over `InputField`.

## Tweens (default: DOTween Pro)

**DOTween Pro is the default tween engine.** Assume `Assets/Plugins/Demigiant/DOTweenPro/` is present.

- Use DOTween shortcut tweens (`DOMove`, `DOFade`, `DOScale`, `DOText` for TMP) instead of hand-rolled coroutine lerps.
- Every tween on a MonoBehaviour target must be killed on destroy — either `.SetLink(gameObject)` or store the `Tween` and `Kill()` it in `OnDisable`/`OnDestroy`.
- Await tweens with UniTask: `await tween.ToUniTask(cancellationToken: ct)` — never `WaitForCompletion()` in new code.
- See [[unity-dotween]] for full rules (sequences, capacity, Pro-only features).

## Logging

- Use `Debug.Log*` only for development; never log inside `Update` without a guard.
- For production logs, route through a project-level `ILogger` abstraction so logs can be muted in shipping builds.

## Forbidden patterns

- Singleton `MonoBehaviour` for shared services when DI is available — see `unity-architecture`.
- `Resources.Load` for new code — use [[unity-addressables]] or direct `[SerializeField]` references.
- Mutable `static` state on MonoBehaviours — survives domain reloads only if `[RuntimeInitializeOnLoadMethod]` clears it.

## Verification checklist (every change)

- [ ] No `GetComponent` / `Find*` calls added inside `Update` / `FixedUpdate`.
- [ ] New configurable values live in a `ScriptableObject`, not as hard-coded literals.
- [ ] New scripts live in the correct `*.asmdef` (editor-only code is not pulled into runtime).
- [ ] No new `public` field exists solely for Inspector exposure — use `[SerializeField] private`.
- [ ] No comments added — neither `///` doc blocks nor inline `//`.
- [ ] When Odin is present, no `[Header]` used — Odin grouping/labelling attributes instead.
- [ ] No `Debug.Log` left in hot paths.
- [ ] Every added/renamed/deleted path under `Assets/` has its `.meta` change paired — `check-meta.sh` passes.