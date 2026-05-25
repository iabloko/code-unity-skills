---
name: unity-performance
description: Diagnose and fix Unity performance issues — GC allocations, hot-path inefficiencies, draw-call/batching problems, Update-loop costs, and URP-specific concerns. Use the Unity Profiler and Frame Debugger to measure before changing. Apply whenever a change is in a per-frame path, when frame-time / GC complaints arise, or when optimizing for mobile / VR.
---

# Unity Performance

Rule zero: **measure first**. Don't optimize without a profile trace pointing at the cost. Don't micro-optimize cold code.

Pair with [[unity-conventions]] (caching `GetComponent` etc.) and [[unity-architecture]] (extracting logic from `Update` into testable, predictable shapes).

## Measure first — the tools

- **Window > Analysis > Profiler** — primary tool. Attach to a Player build for representative numbers (Editor numbers lie).
- **Profile Analyzer** package — compare two captures.
- **Frame Debugger** — per-draw-call inspection (Window > Analysis > Frame Debugger).
- **Memory Profiler** package — heap snapshots, leaks.
- **Deep Profile** — toggles instrumentation on every method; expensive but pinpoints `Update`-loop costs. Use briefly.
- **Player log** — `Application.targetFrameRate`, dynamic resolution, and DRC events log here.

Always profile on the target platform if it isn't desktop. Mobile numbers are not desktop numbers.

## Hot list — the cheap wins first

In rough order of frequency-of-impact:

### 1. GC allocations per frame

Any `_` next to a line in the Profiler's GC Alloc column on a per-frame path is a smell.

Common offenders:

- `string.Format` / interpolation `$"..."` inside `Update`.
- `foreach` over `List<T>` is fine in modern Unity, but `foreach` over `IEnumerable<T>` allocates an enumerator boxing — keep concrete collection types.
- LINQ in hot paths (`Where`, `Select`, `OrderBy`) — replace with explicit loops.
- `new Vector3(...)` in tight loops is fine (struct), but `new SomeClass(...)` per frame is not.
- Closures that capture variables → delegate allocation. Use cached delegates or `Action`/`Func` fields.
- `gameObject.tag == "Player"` allocates? No (`tag` getter is fine), but `CompareTag("Player")` is still preferred (avoids string allocation on some platforms).
- `GetComponents`/`GetComponentsInChildren` returning arrays — use the `List<T>` overload with a reusable list.
- DOTween tweens / sequences built inside `Update` — construct on event or reuse with `SetAutoKill(false)` + `Restart()`. Raise `DOTween.SetTweensCapacity` instead of letting the pool grow at runtime (see [[unity-dotween]]).

### 2. Update-loop cost

- Empty `Update` methods on disabled-by-tag MonoBehaviours **still cost** (Unity dispatches them). Remove `Update` if not needed.
- Many objects ticking → one `UpdateManager` that ticks `IUpdatable`s. Especially worth it past ~100 instances.
- Use `LateUpdate` for camera following, `FixedUpdate` only for physics — don't move things in `FixedUpdate` for non-physics reasons.

### 3. Find / lookup APIs

- `FindObjectOfType`, `GameObject.Find`, `SendMessage` — slow and grow with scene size. Inject references via DI ([[unity-architecture]]) or `[SerializeField]`.
- `Camera.main` is now cached in modern Unity but still — cache it once locally.

### 4. Instantiate / Destroy churn

- Pool everything that spawns more than a couple of times per minute. Unity's `UnityEngine.Pool` (≥ 2021) is the default — `ObjectPool<T>`.
- Destroy is async and triggers GC churn. Disable + return to pool instead.

### 5. Physics

- Trigger/Collider counts and Rigidbody counts dominate physics cost — fewer, larger colliders beat many small ones for static geometry.
- `Physics.SyncTransforms` is implicit when you read a Transform after moving a Rigidbody. Batch reads.
- Layer-based collision matrix is faster than per-collision `if` checks.

### 6. Rendering / draw calls (URP)

- **SRP Batcher**: requires shader compatibility. Shader Graph and URP/Lit are compatible by default. Custom shaders need a properly declared `UnityPerMaterial` CBUFFER.
- **GPU instancing**: enable on materials for repeated meshes. SRP Batcher + instancing don't stack — SRP Batcher wins by default; use instancing for procedurally-drawn instances via `Graphics.DrawMeshInstanced`.
- **Static batching**: mark scene meshes Static; combined at build time.
- **Dynamic batching**: small meshes (< 300 verts) only; mostly obsolete with SRP Batcher.
- **Overdraw**: enable Overdraw view in Scene window. Transparent surfaces stack — reduce them on mobile.
- **Post-processing**: each effect is a fullscreen pass. Bloom, depth-of-field, SSAO are expensive on mobile — gate by quality tier.

### 7. UI (uGUI)

- A Canvas rebuilds when **any** child changes. Split canvases by update frequency: static (HUD frame), dynamic (score), input (buttons).
- Disable `Raycast Target` on Images that don't need clicks.
- Avoid `LayoutGroup` + many children at runtime — it rebuilds on every change.
- `TMP_Text.SetText(StringBuilder)` to avoid string allocations.

### 8. Memory

- Big textures dominate mobile memory. Check max sizes in import settings per platform.
- `Resources.Load` keeps assets loaded until `Resources.UnloadUnusedAssets`. Prefer **Addressables** with explicit release.
- Don't subscribe to a long-lived event from a short-lived object without unsubscribing in `OnDisable`/`OnDestroy` — instances leak.

## URP-specific

- **Renderer Features** are global; expensive features (full-screen blits, custom passes) affect all cameras. Gate by camera tag or scriptable renderer asset per scene.
- **Forward+** (URP ≥ 14) lets you have many lights cheaply; legacy Forward limits per-object lights — check the URP asset's lighting mode.
- **Shadow cascades**: 4 cascades is dense for mobile; 1–2 suffices.
- **MSAA**: 2x is the sweet spot on mid-mobile; off if using TAA or FXAA.

## Patterns

### Cache `WaitForSeconds`

```csharp
private static readonly WaitForSeconds _oneSecond = new(1f);
// reuse _oneSecond instead of `yield return new WaitForSeconds(1f)`
```

### Reusable list overload

```csharp
private readonly List<Renderer> _renderers = new();
private void RefreshRenderers()
{
    _renderers.Clear();
    GetComponentsInChildren(_renderers); // no allocation
}
```

### `UnityEngine.Pool.ObjectPool<T>`

```csharp
private readonly ObjectPool<Bullet> _pool = new(
    createFunc: () => Instantiate(_bulletPrefab),
    actionOnGet:  b => b.gameObject.SetActive(true),
    actionOnRelease: b => b.gameObject.SetActive(false),
    actionOnDestroy: b => Destroy(b.gameObject),
    defaultCapacity: 32, maxSize: 256);
```

### `CompareTag` over `==`

```csharp
if (other.CompareTag("Enemy")) // ok
if (other.tag == "Enemy")       // avoid (allocates string on some platforms)
```

### `StringBuilder` for UI text

```csharp
private readonly StringBuilder _sb = new(64);
private void UpdateScore(int s)
{
    _sb.Clear();
    _sb.Append("Score: ").Append(s);
    _scoreText.SetText(_sb);
}
```

### Job System / Burst (when needed)

For large data-parallel loops (1000+ items, ECS-friendly): `IJobParallelFor` + `[BurstCompile]`. Don't reach for it before profiling shows a CPU bottleneck — it adds significant complexity.

## Anti-patterns

- Calling `Camera.main` every frame.
- LINQ chains in `Update`.
- `string.Format` / interpolation in `Update`.
- Building `new List<T>()` per frame.
- `GameObject.SetActive` toggling a deep hierarchy every frame (triggers many awakes).
- Subscribing to `Application.onLowMemory` to "release stuff" instead of fixing the allocation pattern.
- Disabling the Profiler "because it's slow in editor" — always re-enable; if editor numbers matter, build a Player and attach.

## Verification checklist

- [ ] A Profiler capture exists showing the cost **before** the change.
- [ ] After the change, GC Alloc on the targeted path is 0 B/frame (or measurably reduced).
- [ ] Frame Debugger draw-call count did not increase (for rendering changes).
- [ ] No new `Find*` / `GetComponent` added inside `Update`.
- [ ] If a pool was added, capacity and max size are tuned to the realistic spawn count.
- [ ] Target-platform profile re-run (mobile/VR if applicable), not just editor numbers.