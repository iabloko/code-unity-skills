---
name: ecslite-performance
description: Keep LeoEcsLite (ecslite) on its fast, allocation-free path — cache pools/filters as fields or DI injects (never `GetPool`/`Filter` in `Run`), access components by `ref`, avoid managed fields/boxing in components, preset `EcsWorld.Config` capacities to avoid resize churn, handle ref-invalidation and structural-change-during-iteration, ship RELEASE builds, and escalate heavy loops to the jobs/native companion packages. Detect first — only applies with `com.leoecscommunity.ecslite`. Use whenever a system's `Run` is in a per-frame path or you're tuning ECS throughput/GC. Measure with the Profiler first.
---

# LeoEcsLite — Performance

ecslite is *chosen for* throughput and zero/low GC; the wins are specific and differ from general Unity tuning. As with [[unity-performance]], **measure first** (Unity Profiler, Deep Profile a frame, watch GC Alloc) — then apply these. Builds on [[ecslite-conventions]] (struct/ref rules) and [[ecslite-systems]] (where to cache).

## Detect first

- `com.leoecscommunity.ecslite` in `manifest.json` ([[ecslite-conventions]]).
- Profile before changing: confirm the hot system in the Profiler and check for per-frame GC.Alloc spikes. Don't optimize a system that isn't hot.

## Cache pools and filters — never resolve them in `Run`

`GetPool<T>()` and `world.Filter<…>().End()` do real work (lookup / mask build). Resolve once in `Init` (or inject), reuse the field forever.

```csharp
sealed class MovementSystem : IEcsInitSystem, IEcsRunSystem {
    EcsFilter _filter;
    EcsPool<Position> _pos;
    EcsPool<Velocity> _vel;

    public void Init (EcsSystems systems) {
        var w = systems.GetWorld ();
        _filter = w.Filter<Position> ().Inc<Velocity> ().End ();
        _pos = w.GetPool<Position> ();
        _vel = w.GetPool<Velocity> ();
    }

    public void Run (EcsSystems systems) {
        foreach (int e in _filter) {
            ref var p = ref _pos.Get (e);
            ref var v = ref _vel.Get (e);
            p.X += v.X; p.Y += v.Y;
        }
    }
}
```

With `ecslite-di`, `EcsPoolInject`/`EcsFilterInject` give you the same caching for free ([[ecslite-systems]]).

## Access by `ref`, iterate by filter

- Always `ref var c = ref pool.Get(e)` — a copy both wastes the write ([[ecslite-conventions]]) and copies the whole struct.
- Iterate entities via the filter `foreach`; don't scan `GetRawEntities()` in production (debug-only).
- Inside the loop, `pool.Get` is safe (the filter guarantees presence) — no need for `Has` guards on filtered components.

## Keep components allocation-free

- Prefer blittable, value-type fields. Avoid `string`, `List<>`, `object` in components on the hot path.
- A managed field keeps the referenced object alive after recycle → GC pressure / leaks. If you must hold one, implement `IEcsAutoReset` to null/clear it on recycle ([[ecslite-conventions]]).
- Don't allocate inside `Run` (no `new List<>()`, LINQ, lambdas capturing locals, string concatenation). Reuse buffers held in a system field (or a component cleared via `IEcsAutoReset`).

## Preset world capacities to avoid resize churn

For large or known-size worlds, pass an `EcsWorld.Config` so backing arrays don't grow repeatedly during warmup. All fields default to **512**:

```csharp
var world = new EcsWorld (new EcsWorld.Config {
    Entities          = 8192,   // initial live-entity capacity
    RecycledEntities  = 2048,   // recycle buffer
    Pools             = 64,     // distinct component types
    Filters           = 64,     // distinct filters
    PoolDenseSize     = 8192,   // initial per-pool dense storage
    PoolRecycledSize  = 2048,   // per-pool recycle buffer
});
```

Filter capacity can also be hinted at build time: `world.Filter<T>().End(capacity)`. Size to expected peak; oversizing wastes memory, undersizing causes resizes mid-frame.

## Structural changes & ref invalidation

- A `ref` from a pool can be invalidated by an `Add` to **that same pool** (array resize). If you `Add` then keep using an earlier `ref` from the same pool, re-`Get` it ([[ecslite-conventions]]).
- Avoid add/remove of the *filtered* components while iterating that filter — the active set can shift under you. Patterns that stay safe:
  - Produce a one-frame request component now, apply/cleanup in a later system + `DelHere<T>` ([[ecslite-systems]]).
  - Collect target entities into a reused buffer during the loop, mutate after the loop.
- `Del`-ing the last component auto-deletes the entity — fine, but don't then touch that entity id.

## Build configuration

- **Ship RELEASE.** DEBUG compiles all sanitize checks (`Add`/`Get` guards, filter-constraint checks) — real per-call overhead. Develop in DEBUG, profile/ship RELEASE ([[ecslite-conventions]]).
- `LEOECSLITE_NO_SANITIZE_CHECKS` strips checks even in DEBUG for apples-to-apples profiling — never define it while still validating logic.
- Disable `LEOECSLITE_WORLD_EVENTS` / `LEOECSLITE_FILTER_EVENTS` in shipping builds unless something needs the hooks — listeners add per-change cost.

## Escalating heavy loops

When a single system's loop dominates the frame and the work is data-parallel, reach for the companion packages instead of hand-threading (the core is single-thread-only, [[ecslite-conventions]]):

- `ecslite-threads` — chunked multi-threaded filter iteration.
- `ecslite-unity-jobs` — Burst/Job-friendly access to component arrays.
- `ecslite-native` — native-collection-backed worlds for job compatibility.

Confirm the package is in `manifest.json` before using it, and measure that the parallel version actually wins (job scheduling has overhead).

## Anti-patterns

- `GetPool<T>()` / `Filter<…>().End()` inside `Run`.
- `var c = pool.Get(e)` (copy) on the hot path — use `ref`.
- `new`, LINQ, captures, or string building inside `Run`.
- Managed component fields with no `IEcsAutoReset` → GC retention.
- Mutating the filtered set while iterating it.
- Profiling or shipping with full DEBUG sanitize checks on.
- Hand-rolled threads over `EcsWorld` — use the jobs/native packages.

## Verification checklist

- [ ] Hot path confirmed in the Profiler before changes; GC.Alloc checked.
- [ ] Pools and filters are fields set in `Init` / injected — none built in `Run`.
- [ ] Components accessed by `ref`; loop bodies allocate nothing.
- [ ] Components on hot paths are managed-field-free, or clear them via `IEcsAutoReset`.
- [ ] World capacities preset via `EcsWorld.Config` for large/known worlds.
- [ ] No structural change to the filtered components during their own iteration.
- [ ] Shipping build is RELEASE; sanitize/event defines off unless needed.