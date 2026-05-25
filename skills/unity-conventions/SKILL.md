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
- `ProjectSettings/ProjectVersion.txt` → Unity editor version.
- Render pipeline: look for `UniversalRenderPipelineAsset` or `HDRenderPipelineAsset` assets, or the `com.unity.render-pipelines.universal` package.

If any of these are missing, ask before assuming.

## Naming

- Types, methods, properties: `PascalCase`.
- Private fields: `_camelCase` (leading underscore).
- Serialized private fields: `_camelCase` with `[SerializeField]` — never make a field `public` just to expose it in the Inspector.
- Constants: `PascalCase` (not `SCREAMING_CASE`).
- Booleans: prefix with `is/has/can/should` (`_isReady`, `HasTarget`).
- Async methods returning `Task`/`UniTask`: suffix `Async`.

## File / assembly layout

- One public type per file; file name = type name.
- Group code into `*.asmdef`-bounded assemblies by feature, not by layer. Domain code must not reference `UnityEngine.UI` or `UnityEditor`.
- Editor-only code lives under an `Editor/` folder with an editor-only `*.asmdef` (`includePlatforms: ["Editor"]`).
- Tests live under `Tests/Editor` and `Tests/Runtime` with their own `*.asmdef` referencing `UnityEngine.TestRunner` and `UnityEditor.TestRunner`.

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

## Coroutines vs async (default: UniTask)

**UniTask is the default in this user's projects.** Assume `com.cysharp.unitask` is present; if it isn't in `manifest.json`, ask before falling back to coroutines.

- Use `UniTask` / `UniTaskVoid` over `IEnumerator` coroutines and over `Task` for any Unity-thread work. Coroutines are reserved for `WaitForEndOfFrame`-style cases that don't have a UniTask equivalent.
- Always accept a `CancellationToken`. Tie MonoBehaviour-owned work to `destroyCancellationToken` (Unity ≥ 2022.2) or `this.GetCancellationTokenOnDestroy()` (UniTask helper).
- Use `UniTask.WhenAll` / `UniTask.WhenAny` instead of manual flag juggling.
- For fire-and-forget on a Unity event, declare `async UniTaskVoid` and call with `.Forget()` — surfaces unhandled exceptions; never use `async void` (except for `UnityEvent`-bound handlers that the inspector wires up).
- Avoid `.GetAwaiter().GetResult()` and `.Task.Wait()` — deadlocks under Unity's sync context.

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
- [ ] No `Debug.Log` left in hot paths.