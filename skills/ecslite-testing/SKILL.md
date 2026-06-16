---
name: ecslite-testing
description: Unit-test LeoEcsLite (ecslite) systems in EditMode with no PlayMode — build a fresh `EcsWorld`, register the system in an `EcsSystems`, seed entities/components, call `Run()` once, then assert on pool state. Covers one-frame/event-flow tests, deterministic stepping, fixtures, and red-green TDD for ECS logic. Detect first — only applies with `com.leoecscommunity.ecslite`. Use whenever adding or changing system logic; ECS logic is plain C#, so prefer fast EditMode `[Test]`s over PlayMode.
---

# LeoEcsLite — Testing

ECS logic in ecslite is **plain, synchronous C#** — no MonoBehaviour, no scene, no frame loop required. That means you test systems as pure functions of world state: seed components, step once, assert. This is a big speed/quality win; lean on it. Builds on [[ecslite-conventions]] and [[ecslite-systems]]; for the general Unity Test Framework rules (assembly defs, EditMode vs PlayMode) see [[unity-testing]], and drive changes red-green per [[running-tdd-cycles]].

## Detect first

- `com.leoecscommunity.ecslite` in `manifest.json` ([[ecslite-conventions]]).
- A test assembly definition referencing the ecslite asmdef + `nunit.framework` (see [[unity-testing]] for asmdef setup). Tests live in EditMode unless they assert MonoBehaviour/scene behavior.

## Default pattern — EditMode, synchronous `[Test]`

`Run()` is synchronous, so a plain `[Test]` is correct — **no `[UnityTest]`, no `UniTask`, no coroutine needed.** (Async-in-test pitfalls only apply to UniTask flows — not here.)

```csharp
using NUnit.Framework;
using Leopotam.EcsLite;

public sealed class MovementSystemTests {
    [Test]
    public void Run_AdvancesPositionByVelocity () {
        // Arrange
        var world = new EcsWorld ();
        var systems = new EcsSystems (world);
        systems.Add (new MovementSystem ()).Init ();

        int e = world.NewEntity ();
        ref var pos = ref world.GetPool<Position> ().Add (e);
        ref var vel = ref world.GetPool<Velocity> ().Add (e);
        vel.X = 2f;

        // Act — one deterministic tick
        systems.Run ();

        // Assert — read back through the pool
        ref var after = ref world.GetPool<Position> ().Get (e);
        Assert.AreEqual (2f, after.X, 1e-5f);

        // Teardown — systems then world (mirrors production)
        systems.Destroy ();
        world.Destroy ();
    }
}
```

Why this shape:
- A fresh `EcsWorld` per test = full isolation, zero shared state.
- `systems.Run()` once steps exactly one frame — deterministic. Call it N times to test multi-frame behavior.
- Assert by reading the pool with `Get` (presence guaranteed by your arrange) or by `Has` for add/remove outcomes.

## Fixture to kill boilerplate

```csharp
public abstract class EcsTestBase {
    protected EcsWorld World;
    EcsSystems _systems;

    protected void Build (params IEcsSystem[] systemsToAdd) {
        World = new EcsWorld ();
        _systems = new EcsSystems (World);
        foreach (var s in systemsToAdd) _systems.Add (s);
        _systems.Init ();
    }

    protected void Step (int frames = 1) {
        for (int i = 0; i < frames; i++) _systems.Run ();
    }

    [TearDown]
    public void TearDown () {
        _systems?.Destroy ();
        World?.Destroy ();
    }
}
```

```csharp
public sealed class DeathSystemTests : EcsTestBase {
    [Test]
    public void ZeroHealth_TagsEntityDead () {
        Build (new DeathSystem ());
        int e = World.NewEntity ();
        World.GetPool<Health> ().Add (e);   // Value defaults to 0

        Step ();

        Assert.IsTrue (World.GetPool<Dead> ().Has (e));
    }
}
```

## Testing one-frame / event flows

A request component should be produced, consumed, and gone. Test the consumer in isolation and assert the **effect**, not the request:

```csharp
[Test]
public void ApplyDamage_ReducesHealth_AndRemovesRequest () {
    Build (new ApplyDamageSystem ());      // do NOT add the DelHere here unless testing cleanup
    int e = World.NewEntity ();
    ref var hp = ref World.GetPool<Health> ().Add (e);
    hp.Value = 100;
    ref var dmg = ref World.GetPool<DamageRequest> ().Add (e);
    dmg.Amount = 30;

    Step ();

    Assert.AreEqual (70, World.GetPool<Health> ().Get (e).Value);
}
```

To test the cleanup contract itself, include the `DelHere<T>()` ([[ecslite-systems]]) in the pipeline and assert `!pool.Has(e)` after `Step()`.

## Multi-world / shared-data tests

- Multiple worlds: `AddWorld(eventsWorld, "events")` before `Init`, seed into the world the system reads, assert on the world it writes.
- Shared services: pass a fake/stub via `new EcsSystems(world, fakeShared)` or `EcsCustomInject<T>` + `.Inject(fake)`. Keep services behind interfaces so tests inject stubs ([[unity-architecture]]).

## TDD loop for a new system

1. **Red**: write the `[Test]` describing the world before/after one `Step()`. Run it — it fails (system does nothing yet).
2. **Green**: implement the minimum `Run` to make it pass.
3. **Refactor**: cache pools/filters in `Init` ([[ecslite-performance]]); tests stay green.

Follow [[running-tdd-cycles]]; run via the headless test runner from [[unity-testing]].

## Anti-patterns

- `[UnityTest]` + coroutine / `async` for logic that's just `systems.Run()` — pure overhead; use `[Test]`.
- Reusing one `EcsWorld` across tests (static/`[OneTimeSetUp]`) — leaks state between cases.
- Asserting on a raw `int` entity id captured before structural changes — pack it or re-query ([[ecslite-conventions]]).
- Testing through a `MonoBehaviour Startup` in PlayMode when the logic is engine-free — slower, flakier, no added coverage.
- Skipping `world.Destroy()` in teardown — leaks across the test run.
- Asserting the request component still exists "to be safe" — assert the effect; the request is one-frame.

## Verification checklist

- [ ] Logic tests are EditMode `[Test]`, not `[UnityTest]`/async.
- [ ] Each test builds a fresh `EcsWorld` and tears it down (`systems.Destroy()` then `world.Destroy()`).
- [ ] Behavior is driven by an explicit number of `systems.Run()` steps.
- [ ] Assertions read pool state (`Get`/`Has`), not cached refs taken before stepping.
- [ ] Services are injected as stubs/fakes behind interfaces.
- [ ] New/changed system logic was written red-green ([[running-tdd-cycles]]).