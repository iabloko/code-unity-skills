---
name: unity-testing
description: "Write and run tests in Unity using the Unity Test Framework — EditMode for plain C# / domain logic, PlayMode for MonoBehaviour and scene behavior. Apply red-green-refactor TDD: write the failing test first, then the minimum code to pass. Use whenever adding or changing logic in a Unity project."
---

# Unity Testing (Unity Test Framework)

Test what is testable cheaply (Domain/Application in EditMode) and only escalate to PlayMode when scene/lifecycle behavior is actually under test.

Pair with [[unity-conventions]] for assembly layout and [[unity-architecture]] for layering.

## Detect first

- `Packages/manifest.json` must contain `com.unity.test-framework`. If absent, ask before adding it.
- Find existing test assemblies: `Glob` for `**/Tests/**/*.asmdef`. Match their location and naming style.
- Check for additional test libraries in `manifest.json`: `com.cysharp.unitask` (UniTask test runners), `nunit` extensions, FluentAssertions.

## EditMode vs PlayMode — pick the cheaper one

| Question                                                       | Use         |
| -------------------------------------------------------------- | ----------- |
| Logic is plain C# (Domain / Application / utilities)           | EditMode    |
| Validating a `ScriptableObject`'s data invariants              | EditMode    |
| Behavior depends on `Awake`/`OnEnable`/`Start`/`Update`        | PlayMode    |
| Needs a real `Time.deltaTime` tick or coroutine timing         | PlayMode    |
| Needs a real scene, physics, animation, or rendering           | PlayMode    |

If a piece of logic only needs PlayMode because it's wrapped in a MonoBehaviour, **refactor**: extract the logic into a plain C# class, test it in EditMode, keep the MonoBehaviour as a thin adapter.

## Assembly layout

```
Assets/Scripts/Feature/Feature.asmdef            (runtime)
Assets/Scripts/Feature/Tests/Editor/             (EditMode tests)
  Feature.Tests.Editor.asmdef
Assets/Scripts/Feature/Tests/Runtime/            (PlayMode tests)
  Feature.Tests.Runtime.asmdef
```

EditMode `*.asmdef` reference essentials:
- `includePlatforms: ["Editor"]`
- `references`: production assembly, `UnityEngine.TestRunner`, `UnityEditor.TestRunner`
- `defineConstraints`: `["UNITY_INCLUDE_TESTS"]`
- `optionalUnityReferences`: `["TestAssemblies"]` (older Unity) or set the test-assembly flag in the asmdef (newer Unity).

PlayMode `*.asmdef`: same as above minus `includePlatforms` (so it runs in players too if you want device runs) and with `UnityEngine.TestRunner` referenced.

## EditMode test pattern

```csharp
using NUnit.Framework;

namespace Game.Feature.Tests
{
    [TestFixture]
    public sealed class DamageCalculatorTests
    {
        [Test]
        public void Calculate_AppliesArmorReduction()
        {
            var calc = new DamageCalculator();

            var result = calc.Calculate(rawDamage: 100, armor: 25);

            Assert.AreEqual(75, result);
        }

        [TestCase(0,   0, 0)]
        [TestCase(50, 50, 25)]
        [TestCase(200, 0, 200)]
        public void Calculate_HandlesBoundaries(int dmg, int armor, int expected)
        {
            Assert.AreEqual(expected, new DamageCalculator().Calculate(dmg, armor));
        }
    }
}
```

- Use `[TestCase]` over multiple near-identical tests.
- Arrange / Act / Assert separated by blank lines.
- One assertion per concept (a single test may use multiple `Assert.*` if they all check one behavior).

## PlayMode test pattern

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

public sealed class EnemySpawnerPlayModeTests
{
    [UnityTest]
    public IEnumerator Spawner_SpawnsOneEnemyPerSecond()
    {
        var go = new GameObject(nameof(EnemySpawner));
        var spawner = go.AddComponent<EnemySpawner>();
        spawner.intervalSeconds = 1f;

        yield return new WaitForSeconds(1.1f);

        Assert.AreEqual(1, spawner.SpawnedCount);

        Object.Destroy(go);
    }
}
```

- `[UnityTest]` returns `IEnumerator`; use `yield return null` for one frame, `WaitForSeconds`, or `WaitUntil(() => ...)`.
- Always destroy GameObjects created during the test (in a `[TearDown]` or at end of method) — leaks pollute later tests.
- Prefer `[SetUp]`/`[TearDown]` for shared fixtures.

## Async / UniTask tests (default)

UniTask is the default async type in this user's projects — write async tests as `UniTask`-returning methods unless a third-party rule says otherwise.

```csharp
[Test]
public async Task Orchestrator_LoadsAndStarts()
{
    var orchestrator = new StartLevelOrchestrator(saveStub, loaderStub, analyticsStub);
    await orchestrator.Execute(levelId: 3, CancellationToken.None);
    Assert.AreEqual(3, loaderStub.LastLoadedLevelId);
}
```

- NUnit's runner awaits `Task`-returning tests; UniTask integrates via `UniTask.ToCoroutine()` for older runners, but modern Unity Test Framework awaits `UniTask` directly.
- Use `[UnityTest] public IEnumerator Foo() => UniTask.ToCoroutine(async () => { ... });` when the test must drive Unity's frame loop (e.g. PlayMode with `UniTask.Yield()`).
- Don't use `.GetAwaiter().GetResult()` or `.Task.Wait()` — deadlocks under Unity's sync context.
- Pass `CancellationToken.None` from tests explicitly; never let production code rely on a default `default(CancellationToken)`.

## Mocks / fakes

- No mocking framework is bundled with Unity. Either:
  - **Hand-roll fakes** for interfaces (preferred for the Domain layer — simple and explicit).
  - Add `NSubstitute` or `Moq` only if the team already uses one.
- Never mock concrete `MonoBehaviour` — test against an interface that the MonoBehaviour implements.

## TDD loop (red → green → refactor)

For each behavior change:

1. **Red**: write the smallest failing EditMode test that pins the new behavior. Run it (headless — see *Running tests* below, with `-testFilter` scoped to the new test); verify it actually fails for the right reason, not from a compile error.
2. **Green**: write the minimum production code to make it pass — no extras (per CLAUDE.md "Simplicity First").
3. **Refactor**: clean up only what you just wrote. Tests must stay green.

Don't write the production code first and then a confirming test — that test doesn't prove anything.

## Running tests

- Editor UI: `Window > General > Test Runner` — when the user is driving.
- **Headless CLI — the default for agents.** Use the bundled runner from the Unity project root:

```sh
bash <skills>/unity-testing/scripts/run-tests.sh                                    # EditMode, full suite
bash <skills>/unity-testing/scripts/run-tests.sh EditMode "Game.Feature.Tests.DamageCalculatorTests"
bash <skills>/unity-testing/scripts/run-tests.sh PlayMode
```

The script locates the editor via `ProjectSettings/ProjectVersion.txt` + Unity Hub default install paths (`UNITY_PATH` env var overrides), refuses to run while the editor has the project open, writes NUnit XML + log into `TestResults/`, and prints a pass/fail summary with the full names of failed tests. Exit code `0` = green, `2` = test failures, anything else = run error.

Raw CLI equivalent, when the script doesn't fit:

```sh
"$UNITY" -batchmode -nographics -projectPath . -runTests -testPlatform EditMode \
    -testResults "$(pwd)/TestResults/results.xml" -logFile "$(pwd)/TestResults/run.log"
```

### Headless gotchas

- **Never pass `-quit` together with `-runTests`** — it kills the editor before tests finish.
- `-testResults` / `-logFile` must be **absolute** paths.
- One editor instance per project: a present `Temp/UnityLockfile` means the editor (or another batch run) has the project open — the run fails immediately. Ask the user to close the editor; after a crash the lockfile may be stale.
- Compile errors abort before any test runs: no results XML, nonzero exit — look for `error CS` in the log, fix, rerun.
- First batch launch after asset changes triggers an import — allow a generous timeout (up to ~10 min on large projects); don't kill the process early.
- `-testFilter` matches full names (`Namespace.Class.Method`; semicolon-separated; regex supported), `-testCategory` matches `[Category]` attributes. Filtered runs keep the red-green loop fast; always finish with the **full suite** before committing.
- PlayMode: keep `-nographics` unless a test genuinely renders — most don't.
- Side effect worth knowing: any batchmode launch imports new assets and generates their `.meta` files (see [[unity-conventions]] on `.meta` hygiene).

## Anti-patterns

- One giant `[Test]` that asserts six unrelated things — split.
- Tests that depend on `Time.realtimeSinceStartup` or `DateTime.Now` directly — inject an `ITimeProvider`.
- `Thread.Sleep` inside tests — use `yield return new WaitForSeconds(...)` (PlayMode) or stub the clock (EditMode).
- Loading real scenes by name from EditMode tests — set up the GameObjects programmatically.
- Tests that call `FindObjectOfType` to locate the system under test — inject explicitly.

## Verification checklist

- [ ] New behavior has a failing test written **before** the code.
- [ ] Logic landed in EditMode tests unless it genuinely requires PlayMode.
- [ ] No `Thread.Sleep` in tests.
- [ ] No new test depends on a hand-authored scene.
- [ ] All created GameObjects are destroyed in `[TearDown]`.
- [ ] Full suite is green before declaring done — `run-tests.sh` exit code `0` (or Test Runner window when the user drives).