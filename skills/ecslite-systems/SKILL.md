---
name: ecslite-systems
description: Compose and wire LeoEcsLite (ecslite) systems — `EcsWorld`/`EcsSystems` setup and teardown order, the system interfaces (`IEcsPreInit/Init/Run/Destroy/PostDestroy`) and execution order, registration-order = run-order, multiple system groups (Update/FixedUpdate/LateUpdate) sharing one world, multiple named worlds, shared data, `ecslite-di` injection (`EcsWorldInject`/`EcsPoolInject`/`EcsFilterInject`/`EcsSharedInject`/`EcsCustomInject` + `Inject()` placement), `ecslite-extendedsystems` (`DelHere<T>` one-frame components, `AddGroup` enable/disable), and bootstrapping ECS inside a Zenject/VContainer host. Detect first — only applies with `com.leoecscommunity.ecslite`. Use whenever creating a system, building the startup/lifecycle, or wiring dependencies.
---

# LeoEcsLite — Systems & Wiring

How systems get composed, ordered, injected, and torn down. Builds on [[ecslite-conventions]] (struct components, pools, filters). For the host-engine architecture around the ECS (where the bootstrap lives, DI container choice) see [[unity-architecture]]; for hot-path concerns in `Run` see [[ecslite-performance]].

## Detect first

- `com.leoecscommunity.ecslite` in `manifest.json` ([[ecslite-conventions]] covers detection).
- `ecslite-di` present? → `using Leopotam.EcsLite.Di;` and `.Inject()` are available. If absent, inject pools/filters manually in `Init`.
- `ecslite-extendedsystems` present? → `using Leopotam.EcsLite.ExtendedSystems;` for `DelHere<T>` and `AddGroup`.
- Host DI container (Zenject/VContainer) — detect per [[unity-architecture]]; it bootstraps the ECS, it doesn't replace `EcsSystems`.

## System interfaces & execution order

A system is a plain class (suffix `System`) implementing one or more interfaces:

| Interface               | Method                    | When                                         |
|-------------------------|---------------------------|----------------------------------------------|
| `IEcsPreInitSystem`     | `PreInit(EcsSystems)`     | during `Init()`, before all `Init`           |
| `IEcsInitSystem`        | `Init(EcsSystems)`        | during `Init()`, after all `PreInit`         |
| `IEcsRunSystem`         | `Run(EcsSystems)`         | every `Run()` call                           |
| `IEcsDestroySystem`     | `Destroy(EcsSystems)`     | during `Destroy()`, before all `PostDestroy` |
| `IEcsPostDestroySystem` | `PostDestroy(EcsSystems)` | during `Destroy()`, after all `Destroy`      |

```csharp
sealed class MovementSystem : IEcsInitSystem, IEcsRunSystem {
    EcsFilter _filter;
    EcsPool<Position> _positions;
    EcsPool<Velocity> _velocities;

    public void Init (EcsSystems systems) {
        EcsWorld world = systems.GetWorld ();
        _filter = world.Filter<Position> ().Inc<Velocity> ().End ();   // build once
        _positions = world.GetPool<Position> ();                        // cache pools
        _velocities = world.GetPool<Velocity> ();
    }

    public void Run (EcsSystems systems) {
        foreach (int e in _filter) {
            ref Position p = ref _positions.Get (e);
            ref Velocity v = ref _velocities.Get (e);
            p.X += v.X;
            p.Y += v.Y;
        }
    }
}
```

**Registration order is execution order** within each phase — `Add` systems in the order their effects must happen.

## Lifecycle & the Unity bootstrap

```csharp
sealed class Startup : MonoBehaviour {
    EcsWorld _world;
    EcsSystems _systems;

    void Start () {
        _world = new EcsWorld ();
        _systems = new EcsSystems (_world);
        _systems
            .Add (new SpawnSystem ())
            .Add (new MovementSystem ())
            .Add (new RenderSyncSystem ())
            .Init ();
    }

    void Update () => _systems?.Run ();

    void OnDestroy () {
        // Order matters: systems first, then world. Null out after.
        if (_systems != null) { _systems.Destroy (); _systems = null; }
        if (_world != null)  { _world.Destroy ();  _world = null; }
    }
}
```

- Destroy **systems before world**, then null both — `OnDestroy` can fire more than once / on disabled objects.
- `new EcsSystems(world, sharedObject)` attaches shared data (below).

## Multiple system groups (Update / FixedUpdate / LateUpdate)

Use **separate `EcsSystems` instances sharing one `EcsWorld`** — there is no built-in "fixed" phase.

```csharp
EcsSystems _update, _fixedUpdate;

void Start () {
    EcsWorld world = new EcsWorld ();
    _update = new EcsSystems (world).Add (new InputSystem ()).Add (new MovementSystem ());
    _update.Init ();
    _fixedUpdate = new EcsSystems (world).Add (new PhysicsStepSystem ());
    _fixedUpdate.Init ();
}

void Update ()      => _update.Run ();
void FixedUpdate () => _fixedUpdate.Run ();

void OnDestroy () {
    _update?.Destroy ();
    _fixedUpdate?.Destroy ();
    // destroy the shared world exactly once, after all groups
}
```

Destroy each group, then the shared world **once**.

## Multiple named worlds

A common pattern is a dedicated **events/requests world** so transient event entities don't churn the main world:

```csharp
_systems = new EcsSystems (mainWorld);
_systems
    .AddWorld (new EcsWorld (), "events")
    .Add (new ProduceEventsSystem ())
    .Add (new ConsumeEventsSystem ())
    .Init ();

// inside a system:
EcsWorld events = systems.GetWorld ("events");
```

Each added world must be destroyed too (track and `Destroy()` them in `OnDestroy`).

## Shared data

Pass a single shared object (your service bag / context) to every system:

```csharp
sealed class SharedData {
    public IConfig Config;
    public ISaveStore Save;
}

var shared = new SharedData { Config = config, Save = save };
var systems = new EcsSystems (world, shared);

// inside a system:
public void Init (EcsSystems systems) {
    SharedData s = systems.GetShared<SharedData> ();
}
```

This is the seam for handing host-engine services to systems — keep services behind interfaces ([[unity-architecture]]).

## Dependency injection — `ecslite-di`

With `ecslite-di`, declare dependencies as fields and call `.Inject()` once, **after** all `Add`/`AddWorld`, **before** `Init`:

```csharp
using Leopotam.EcsLite.Di;

sealed class DamageSystem : IEcsRunSystem {
    readonly EcsWorldInject _world = default;                          // default world
    readonly EcsPoolInject<Health> _health = default;                 // pool
    readonly EcsFilterInject<Inc<Health, DamageRequest>> _filter = default;   // filter (Inc up to 8)
    readonly EcsFilterInject<Inc<Health>, Exc<Dead>> _alive = default;        // Inc + Exc (Exc up to 4)
    readonly EcsSharedInject<SharedData> _shared = default;           // GetShared<T>()
    readonly EcsCustomInject<IClock> _clock = default;                // custom data via Inject(...)

    public void Run (EcsSystems systems) {
        foreach (int e in _filter.Value) {                            // every inject is accessed via .Value
            ref Health h = ref _health.Value.Get (e);
            // ...
        }
    }
}
```

```csharp
var systems = new EcsSystems (new EcsWorld ());
systems
    .Add (new DamageSystem ())
    .AddWorld (new EcsWorld (), "events")
    .Inject (clock)        // params object[] → fills matching EcsCustomInject<T>
    .Init ();
```

- Access **everything through `.Value`**.
- `Inc<...>` takes up to 8 types, `Exc<...>` up to 4; extend with structs implementing `IEcsInclude`/`IEcsExclude`.
- `.Inject(params object[])` feeds `EcsCustomInject<T>` (T must be a `class`); `EcsSharedInject<T>` pulls from the `EcsSystems` shared object.

## One-frame / event components — `ecslite-extendedsystems`

`DelHere<T>()` inserts a built-in system that removes component `T` from every entity at that point in the pipeline — the idiom for one-frame "event"/"request" components ([[ecslite-conventions]]):

```csharp
using Leopotam.EcsLite.ExtendedSystems;

systems
    .Add (new ProduceDamageRequestsSystem ())
    .Add (new ApplyDamageSystem ())
    .DelHere<DamageRequest> ()          // consumed; gone before next frame
    .Add (new DeathSystem ())
    .DelHere<DamageRequest> ("events")  // custom world must be AddWorld'd before DelHere on it
    .Init ();
```

Place `DelHere<T>` **after** the last system that reads `T`.

## Enable/disable groups — `AddGroup`

Toggle a block of systems collectively by emitting a state event:

```csharp
systems
    .AddGroup ("Combat", false, null,           // name, startEnabled, eventWorldName, systems...
        new TargetingSystem (),
        new AttackSystem ())
    .Add (new CombatToggleSystem ())
    .Init ();

// flip it on:
ref var evt = ref world.GetPool<EcsGroupSystemState> ().Add (world.NewEntity ());
evt.Name = "Combat";
evt.State = true;
```

Non-string names (enum/int/custom `IComparable`) use the generic `EcsGroupSystemState<T>` pool.

## Bootstrapping inside Zenject / VContainer

The host DI container builds and owns the bootstrap; the ECS keeps its own composition root.

- Construct `EcsWorld` + `EcsSystems` in an installer / `LifetimeScope` (or a `Startup` resolved by it).
- Pass host services **into** systems via **shared data** or **`EcsCustomInject<T>`** (behind interfaces) — do **not** make systems resolve from the container or use `FindObjectOfType`.
- Drive `Run()` from the host's tick (`ITickable`/`IFixedTickable` in Zenject, `Update` in a MonoBehaviour) and call `Destroy()` from the scope's disposal.
- Keep the world/systems single-owned; never resolve a second `EcsWorld` by accident.

## Debugging

- `ecslite-unityeditor`: add its `EcsWorldDebugSystem` (and per-entity debug views) to inspect live entities/components in the Unity Inspector during Play.
- `world.GetRawEntities()` / `world.GetComponents(entity, ref object[] list)` expose internals for ad-hoc inspection — debug only.
- `LEOECSLITE_WORLD_EVENTS` / `LEOECSLITE_FILTER_EVENTS` enable listener hooks ([[ecslite-conventions]]).

## Anti-patterns

- `GetPool<T>()` / `world.Filter<…>().End()` inside `Run` — build in `Init` or inject ([[ecslite-performance]]).
- Destroying the world before its systems, or destroying a shared world more than once.
- A "god system" doing input + simulation + rendering — split by responsibility; order via registration.
- Systems reaching into the Zenject/VContainer container or `FindObjectOfType` — inject via shared/custom data.
- `DelHere<T>` placed before a system that still reads `T`.
- Forgetting to `Destroy()` extra worlds added with `AddWorld`.

## Verification checklist

- [ ] Systems are suffixed `System` and implement only the interface phases they use.
- [ ] Pools and filters are built in `Init` (or injected), never in `Run`.
- [ ] Teardown destroys systems before world(s); each `AddWorld` world destroyed exactly once.
- [ ] Fixed-step logic is a separate `EcsSystems` sharing the world, driven from `FixedUpdate`.
- [ ] `.Inject()` is called after all `Add`/`AddWorld` and before `Init`; injects read via `.Value`.
- [ ] One-frame components are cleaned up with `DelHere<T>` after their last reader.
- [ ] Host services enter systems via shared data / `EcsCustomInject`, not container lookups.