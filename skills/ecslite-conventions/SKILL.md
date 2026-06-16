---
name: ecslite-conventions
description: Write correct LeoEcsLite (ecslite) code — data-only struct components, the EcsPool API (`Add`/`Get`/`Has`/`Del`) and exactly what throws in DEBUG, `ref` mutation discipline and ref-invalidation, filters (`Inc`/`Exc`, build-once), entity lifecycle and auto-delete, `IEcsAutoReset` for managed fields, `EcsPackedEntity` for cross-frame refs, DEBUG-vs-RELEASE sanitize checks, thread-safety. Detect first — only applies when `com.leoecscommunity.ecslite` is in `Packages/manifest.json`. Use whenever editing C# that uses `Leopotam.EcsLite` (components, systems, pools, filters).
---

# LeoEcsLite — Conventions

LeoEcsLite is a lightweight, allocation-free ECS framework (`namespace Leopotam.EcsLite`). The failure modes here are *specific and silent* — struct copies that drop your mutation, checks that only fire in DEBUG, refs that go stale after a structural change. This skill is the foundation; pair it with [[ecslite-systems]] (wiring/lifecycle/DI), [[ecslite-testing]] (EditMode TDD), and [[ecslite-performance]] (hot-path rules). For host-engine code around the ECS, [[unity-conventions]] still applies.

## Detect first

- `Packages/manifest.json` contains `"com.leoecscommunity.ecslite"`.
- Grep `Assets/**/*.cs` for `using Leopotam.EcsLite;`.
- Companion packages change what's available: `ecslite-di` (`Leopotam.EcsLite.Di`), `ecslite-extendedsystems` (`Leopotam.EcsLite.ExtendedSystems`), `ecslite-unityeditor` (inspector debug). Check the manifest before using their APIs — see [[ecslite-systems]].
- If the project mixes ecslite with another ECS (Unity DOTS/Entities, Morpeh), do **not** blend their APIs — ask.

## Components are data, nothing else

```csharp
// Good — flat data, no logic, no inheritance.
struct Velocity {
    public float X;
    public float Y;
}

// Tag / marker component — empty struct is fine and free.
struct Dead { }

// One-frame "request"/"event" component — carries intent for one tick, then removed.
struct DamageRequest {
    public int Amount;
    public EcsPackedEntity Source;
}
```

Rules:
- Components are **`struct`**, never `class`. No methods beyond `IEcsAutoReset`. No properties with logic, no constructors that "do work."
- No behavior in components — behavior lives in systems ([[ecslite-systems]]).
- Keep them small and prefer blittable fields; managed reference fields need `IEcsAutoReset` (below).

## EcsPool — the only way to touch component data

```csharp
EcsPool<Velocity> pool = world.GetPool<Velocity>();

ref Velocity v = ref pool.Add (entity);   // create; DEBUG-throws if it already exists
ref Velocity v = ref pool.Get (entity);   // read/write; DEBUG-throws if missing
bool has       = pool.Has (entity);        // safe presence check, never throws
pool.Del (entity);                          // remove; deletes the entity if it was the last component
```

- **Guard with `Has` or know your filter guarantees it.** `Add` on an existing component and `Get` on a missing one throw — *only in DEBUG*. In RELEASE they read/write garbage instead of throwing. Never rely on the throw as control flow; never ship code whose correctness depends on it.
- `Del` of the last component on an entity **auto-deletes the entity**. Don't also call `DelEntity` — that double-frees.
- On recycle, value-type fields reset to default automatically. Managed reference fields do **not** clear themselves usefully — see `IEcsAutoReset`.
- **Cache the pool** (field set in `Init` or injected via `EcsPoolInject<T>`); calling `GetPool<T>()` inside `Run` every frame is a [[ecslite-performance]] smell.

## `ref` discipline — the #1 silent bug

A component is a struct. Read it into a plain local and you get a **copy**; your writes go nowhere.

```csharp
// WRONG — mutates a throwaway copy, pool is unchanged.
Velocity v = pool.Get (entity);
v.X += dt;                       // lost

// RIGHT — alias the storage with ref.
ref Velocity v = ref pool.Get (entity);
v.X += dt;                       // persists
```

**Ref invalidation:** a `ref` into a pool can be invalidated by a structural change to *that same pool* (an `Add` may resize its backing array). If you `Add` to a pool after taking a `ref` from it, re-`Get` before using the old ref again. Don't hold a pool `ref` across calls that add/remove components of the same type.

## Entities are `int` — don't store them raw across frames

```csharp
int entity = world.NewEntity ();
world.DelEntity (entity);   // removes all components, recycles the id
```

- An entity id is **recycled** after deletion. A bare `int` you stashed last frame may now point at a *different* entity. To keep a reference across frames, pack it:

```csharp
EcsPackedEntity packed = world.PackEntity (entity);
// ...later, possibly next frame...
if (packed.Unpack (world, out int alive)) {
    // alive is still the same entity; safe to use
}

// Carries its own world reference (handy in multi-world setups):
EcsPackedEntityWithWorld p2 = world.PackEntityWithWorld (entity);
if (p2.Unpack (out EcsWorld w, out int e)) { /* ... */ }
```

Store `EcsPackedEntity` in components/fields that outlive a single system pass. Compare/validate with `Unpack` — never assume a stored raw `int` is still valid.

## Filters — declare the query, build it once

```csharp
// Entities that HAVE Weapon and Position, but do NOT have Dead.
EcsFilter filter = world.Filter<Weapon> ().Inc<Position> ().Exc<Dead> ().End ();

foreach (int entity in filter) {
    ref Weapon w = ref weaponPool.Get (entity);   // pool.Get is safe here — the filter guarantees presence
}
```

- `Filter<T>()` seeds the include list with `T`; chain `.Inc<>()` to add more required components, `.Exc<>()` to exclude, then `.End()`.
- You **cannot** `Inc` and `Exc` the same component, and constraints must be unique — DEBUG-throws otherwise.
- The world **caches filters** by their constraint set: building the same query returns the same instance. Still, build filters **once** (store in a field / inject `EcsFilterInject`), not inside `Run` — see [[ecslite-performance]].
- Avoid structural changes (add/remove the filtered components) while iterating a filter; collect targets first or defer via one-frame components + `DelHere<T>` ([[ecslite-systems]]).

## `IEcsAutoReset` — for components with managed fields

When a component holds a reference (class instance, array, `List<>`, etc.), implement `IEcsAutoReset<T>` so the reference is cleared (or a buffer reused) when the component is recycled — otherwise the pool keeps the managed object alive and you leak / read stale data.

```csharp
struct ViewLink : IEcsAutoReset<ViewLink> {
    public GameObject Go;          // managed reference
    public List<int> Buffer;       // reusable buffer

    public void AutoReset (ref ViewLink c) {
        c.Go = null;               // drop the reference so GC can reclaim
        c.Buffer ??= new List<int> ();
        c.Buffer.Clear ();
    }
}
```

`AutoReset` runs for a brand-new instance and again after the component is removed (before it returns to the pool). Note: this fork has **no** `IEcsAutoCopy` and `EcsPool` has **no** `Copy` method — don't reach for them.

## DEBUG vs RELEASE — know which checks vanish

- All sanitize checks (`Add` on existing, `Get` on missing, duplicate/conflicting filter constraints, "can't change built mask") compile **only in DEBUG**.
- **Develop in DEBUG**, ship RELEASE. A bug masked by "it threw in DEBUG so I never hit it" becomes silent corruption in RELEASE.
- `LEOECSLITE_NO_SANITIZE_CHECKS` strips the checks even in DEBUG (perf profiling) — don't define it while developing logic.
- Optional event hooks are behind defines: `LEOECSLITE_WORLD_EVENTS` (`IEcsWorldEventListener`), `LEOECSLITE_FILTER_EVENTS` (`IEcsFilterEventListener`).

## Thread safety

LeoEcsLite is **not thread-safe and never will be.** All world/pool/filter access happens on one thread. For parallel work use the jobs/native companion packages ([[ecslite-performance]]) — don't touch `EcsWorld` from a worker thread.

## Anti-patterns

- `var v = pool.Get(e); v.X = …;` — mutating a copy. Use `ref`.
- `class` components, or components with methods/logic.
- Relying on `Add`/`Get` throwing to detect presence — gone in RELEASE. Use `Has`.
- Calling `DelEntity` right after `Del`-ing the last component — double free.
- Storing a raw `int` entity id across frames — use `EcsPackedEntity`.
- Building `world.Filter<…>().End()` or calling `GetPool<T>()` inside `Run`.
- Managed field in a component with no `IEcsAutoReset` — leak / stale reference.
- Touching the world off the main thread.

## Verification checklist

- [ ] `com.leoecscommunity.ecslite` confirmed in `manifest.json` before any `using Leopotam.EcsLite;` was added.
- [ ] Every component is a `struct` with data only.
- [ ] Every pool read that is mutated uses `ref … = ref pool.Get(…)`.
- [ ] No reliance on DEBUG-only throws for control flow; presence checked via `Has` or guaranteed by a filter.
- [ ] Components with managed/reference fields implement `IEcsAutoReset`.
- [ ] Entity references that outlive one system pass are stored as `EcsPackedEntity`.
- [ ] Filters and pools are cached/injected, not built inside `Run`.
- [ ] No structural change to a pool while iterating a ref/filter over it.