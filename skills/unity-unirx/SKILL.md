---
name: unity-unirx
description: Apply UniRx for reactive programming in Unity — `IObservable<T>`, `ReactiveProperty<T>`, `Subject<T>`, ObservableTriggers, and `AddTo` lifetime management. Detect first — UniRx is optional in this user's projects. Use it only when the project already depends on it; otherwise prefer plain events / UniTask / C# `event`. Use whenever wiring state-binding (model→view), observing input streams, or coordinating debounce/throttle/combineLatest flows.
---

# UniRx (conditional)

UniRx is **not a default** in this user's projects — it's pulled in selectively. Detect before using; if absent, do not introduce it without asking. When it *is* present, lean into it for reactive state and stream-of-events scenarios; don't reimplement `Observable`-shaped logic with hand-rolled events.

Pair with [[unity-conventions]] (UniTask remains the default for one-shot async — UniRx is for streams), [[unity-architecture]] (`ReactiveProperty` lives in the Application layer; subscriptions live in Presentation), and [[unity-performance]] (every subscription that isn't disposed is a leak).

## Detect first

- `Packages/manifest.json` for `com.neuecc.unirx` (UPM) or `Assets/Plugins/UniRx/` (in-repo install).
- Grep `Assets/**/*.cs` for `using UniRx;` to confirm existing usage and the style the codebase follows.
- If **R3** (`com.cysharp.r3`, UniRx's modern successor) is present *instead*, do not use UniRx APIs — ask which is preferred. The two should not coexist in new code.
- If neither is present and the user asks for "reactive" logic, propose either: (a) plain C# `event` + UniTask for low-rate cases, or (b) adding UniRx/R3 explicitly. Don't smuggle a dependency in.

## When UniRx earns its weight

| Scenario                                                  | Use UniRx?                          |
| --------------------------------------------------------- | ----------------------------------- |
| Model→View binding (HP bar follows `Health` value)        | Yes — `ReactiveProperty<int>`       |
| Combine multiple streams (input + cooldown gate)          | Yes — `CombineLatest`               |
| Debounce / throttle (search field, double-tap detection)  | Yes — `Throttle`, `Debounce`        |
| Single-shot async (load level, fade in)                   | No — UniTask ([[unity-conventions]]) |
| Cross-system event (player died → UI / analytics / SFX)   | Use the DI container's signal/pubsub (Zenject `SignalBus` / MessagePipe) — see [[unity-architecture]] |
| One C# class fires, one listens                           | C# `event` — UniRx is overkill      |

## Lifecycle — non-negotiable

Every `Subscribe` returns an `IDisposable`. **Every subscription must be disposed**, otherwise the subscription keeps the target alive (memory leak) and callbacks fire on destroyed objects.

Two acceptable patterns:

### 1. `AddTo(this)` (preferred for MonoBehaviour)

```csharp
public sealed class HealthBarView : MonoBehaviour
{
    [SerializeField] private Image _fill;
    private IHealthModel _model; // injected

    private void Start()
    {
        _model.Health
            .Subscribe(hp => _fill.fillAmount = hp / 100f)
            .AddTo(this); // auto-disposes on OnDestroy
    }
}
```

`AddTo(MonoBehaviour)` hooks the disposable to that object's lifetime via a hidden `ObservableDestroyTrigger`.

### 2. `CompositeDisposable` (preferred for plain C# classes / many subscriptions)

```csharp
public sealed class CombatPresenter : IDisposable
{
    private readonly CompositeDisposable _disposables = new();

    public CombatPresenter(IInputSource input, IPlayer player)
    {
        input.Attack
            .Where(_ => player.CanAttack.Value)
            .Subscribe(_ => player.Attack())
            .AddTo(_disposables);
    }

    public void Dispose() => _disposables.Dispose();
}
```

Wire `Dispose` through the DI container's lifetime ([[unity-architecture]]).

### Never

- `.Subscribe(...)` without storing or `AddTo`-ing the result — silent leak.
- Storing the disposable in a `static` field — never gets disposed.

## `ReactiveProperty<T>` and friends

The bread-and-butter for state binding:

```csharp
public sealed class Player : IPlayer
{
    public IReactiveProperty<int> Health { get; } = new ReactiveProperty<int>(100);
    public IReadOnlyReactiveProperty<bool> IsAlive => _isAlive;
    private readonly ReactiveProperty<bool> _isAlive;

    public Player()
    {
        _isAlive = Health.Select(hp => hp > 0).ToReactiveProperty();
    }
}
```

- Expose `IReadOnlyReactiveProperty<T>` from interfaces — writes belong to the owner.
- `ReactiveCollection<T>` / `ReactiveDictionary<TKey, TValue>` for observable collections (`ObserveAdd`, `ObserveRemove`, `ObserveCountChanged`).
- `Value` getter/setter is non-observing; only `.Subscribe(...)` reacts.

## Subjects

- `Subject<T>` — `OnNext` / `OnError` / `OnCompleted`. Use for explicit emit points (input events, domain events).
- `BehaviorSubject<T>` — replays the last value to new subscribers. Often you want `ReactiveProperty<T>` instead.
- `ReplaySubject<T>(bufferSize)` — replays N values. Rare; usually a sign you should restructure.
- `AsyncSubject<T>` — only emits on completion. Mostly obsolete; use UniTask.

Never expose a `Subject<T>` directly; expose `IObservable<T>` and keep `OnNext` private to the owner.

## Unity-specific helpers (UniRx.Triggers)

```csharp
using UniRx.Triggers;

// Per-frame stream of Update calls (rate-limit, sample, etc.)
this.UpdateAsObservable()
    .Where(_ => _input.IsHeld)
    .Subscribe(_ => DoSomething())
    .AddTo(this);

// Collider events as a stream
this.OnTriggerEnterAsObservable()
    .Subscribe(other => OnHit(other))
    .AddTo(this);

// Button click stream
_button.OnClickAsObservable()
    .ThrottleFirst(TimeSpan.FromMilliseconds(300)) // anti-spam
    .Subscribe(_ => StartLevel())
    .AddTo(this);
```

Use these instead of declaring an `Update`/`OnTriggerEnter` method that immediately delegates to a `Subject`.

## Common operators (the 90%)

| Operator             | Use                                                            |
| -------------------- | -------------------------------------------------------------- |
| `Where(p)`           | Filter                                                         |
| `Select(f)`          | Map                                                            |
| `DistinctUntilChanged()` | Suppress consecutive duplicates (often after `Select`)     |
| `Throttle(ts)`       | Emit only after `ts` of silence (search box)                   |
| `Debounce(ts)`       | Alias of `Throttle` in UniRx                                   |
| `ThrottleFirst(ts)`  | Emit first, ignore rest within window (anti-spam click)        |
| `Sample(ts)`         | Emit latest value every `ts`                                   |
| `CombineLatest(b)`   | Emit when any source changes, with the latest of each          |
| `WithLatestFrom(b)`  | Like CombineLatest but only fires on `this`'s emissions        |
| `Merge(others...)`   | Interleave streams of the same type                            |
| `SkipWhile`/`TakeWhile` | Bounded streams                                            |
| `Buffer(count)` / `Buffer(ts)` | Batch into windows                                   |

## UniTask interop

UniTask remains the default for one-shot async; bridge when needed:

```csharp
// First emission, then complete (rxified one-shot)
int hp = await player.Health.FirstAsync().ToUniTask(cancellationToken: ct);

// Convert UniTask to single-value Observable (rare)
IObservable<Level> levelLoad = LoadLevel(id).ToObservable();
```

Don't convert just to use UniRx operators on a single value — use `if`/`await` directly.

## Combining with DI

- **Zenject**: UniRx integrates naturally. Bind `IReactiveProperty<T>` from a model and `[Inject]` it into views. Don't use UniRx as a *replacement* for `SignalBus` — signals are typed, discoverable events; observables are streams of value-over-time.
- **VContainer**: same pattern; register the model with the right lifetime so its `ReactiveProperty` instances survive subscriber churn.

## Anti-patterns

- `Observable.EveryUpdate().Subscribe(_ => /* expensive */)` — same cost as a `MonoBehaviour.Update` plus subscription overhead; use `Update` directly if you don't need rx operators.
- `Subscribe(...)` whose return value is discarded — instant leak, will fire on dead targets.
- Exposing a public `Subject<T>` from a service — anyone can `OnNext` and break invariants. Expose `IObservable<T>`, keep emit private.
- Putting business state inside a `Subject<T>` instead of `ReactiveProperty<T>` — Subjects don't replay current value, so late subscribers miss state.
- Chaining 8+ operators to emulate a state machine — at that point, write a real state machine ([[unity-architecture]]).
- Using UniRx for a single C# `event` use-case ("X happens, Y reacts, once") — `event Action` is faster, simpler, no dispose burden.
- `.Wait()` / `.ToTask().Result` on an `IObservable` — UniTask path is the one to use.
- Mixing UniRx and R3 in the same assembly.

## Verification checklist

- [ ] UniRx is confirmed present in `manifest.json` / `Assets/Plugins/UniRx/` before any `using UniRx;` was added.
- [ ] Every new `.Subscribe(...)` either ends in `.AddTo(this)` (MonoBehaviour) or `.AddTo(_disposables)` (plain class with `Dispose`).
- [ ] No new public `Subject<T>` exposed — interfaces return `IObservable<T>` only.
- [ ] State that needs current-value replay uses `ReactiveProperty<T>`, not `Subject<T>`.
- [ ] No `Observable.EveryUpdate()` introduced where a plain `Update` would do.
- [ ] If R3 is in the project, UniRx was not introduced.