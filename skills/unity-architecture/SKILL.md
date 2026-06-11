---
name: unity-architecture
description: Apply Clean Architecture and design patterns (State Machine, Chain of Responsibility, Orchestrator) in Unity. Detect the project's DI container (Zenject preferred over VContainer) and use it instead of singletons. Use whenever designing a new feature, refactoring a MonoBehaviour, or wiring services together.
---

# Unity Architecture

Goal: keep Unity-specific code (MonoBehaviours, ScriptableObjects, asset references) at the edges, and put business logic in plain C# that is testable without entering Play Mode.

Pair with [[unity-conventions]] for naming / serialization rules.

## Detect first — DI container

Run these checks **before** writing any wiring code. Cache the result for the session.

1. Grep `Packages/manifest.json` for `"com.svermeulen.extenject"` or `"jp.hadashikick.vcontainer"`.
2. Grep `Assets/**/*.cs` for `using Zenject;` or `using VContainer;`.

**Decision rule (priority):**

| Found                      | Use                                       |
| -------------------------- | ----------------------------------------- |
| Zenject                    | Zenject (`Installer`, `[Inject]`, `SignalBus`) |
| VContainer (no Zenject)    | VContainer (`LifetimeScope`, `IContainerBuilder`) |
| Neither                    | **Ask the user.** Don't invent a third container. Don't roll your own service locator. |

Never mix Zenject and VContainer in the same assembly.

### Zenject quick rules

- New services bind in an `Installer` (`MonoInstaller` for scene scope, `ScriptableObjectInstaller` for project scope).
- Inject through constructors for plain C# classes and `[Inject]` methods for MonoBehaviours — never field injection on shipping code.
- Use `SignalBus` for cross-cutting events; do not use `static event`.
- Factories: `IFactory<T>` / `PlaceholderFactory<T>` instead of `new` on prefabs.

### VContainer quick rules

- New services register in a `LifetimeScope.Configure(IContainerBuilder builder)`.
- Prefer constructor injection. For MonoBehaviours that must be in a scene, use `builder.RegisterComponentInHierarchy` or `RegisterComponentInNewPrefab`.
- Use `IPublisher<T>` / `ISubscriber<T>` from MessagePipe (if present) for events.

## Layering

Aim for three layers per feature:

```
Domain      ← plain C#, no UnityEngine references, fully unit-testable
Application ← use-cases / orchestrators, depend on Domain + interfaces
Presentation← MonoBehaviours, UI Toolkit / uGUI, ScriptableObject configs
```

Rules:

- Domain must compile in a non-Unity project (no `UnityEngine.*`, no `Object`-derived bases).
- Application defines **interfaces** (`IInputSource`, `ISaveStore`, `ITimeProvider`); Presentation implements them.
- Presentation depends inward only — Domain never `using`s Presentation.
- Cross-layer wiring lives in the DI installer, not in constructors of unrelated classes.

## Patterns

### State Machine

Use when a MonoBehaviour has more than ~2 boolean flags driving behavior, or when `Update` contains an `if/else` chain over a `State` enum.

Skeleton:

```csharp
public interface IState
{
    void Enter();
    void Tick(float dt);
    void Exit();
}

public sealed class StateMachine
{
    private IState _current;
    public void ChangeState(IState next)
    {
        _current?.Exit();
        _current = next;
        _current.Enter();
    }
    public void Tick(float dt) => _current?.Tick(dt);
}
```

- States are plain C# classes; the MonoBehaviour only forwards `Update → StateMachine.Tick`.
- State transitions belong inside states (`ChangeState(new IdleState(...))`) or in a dedicated transition table — not scattered across MonoBehaviours.

### Chain of Responsibility

Use for ordered handlers where each can either handle or pass: input filters, damage modifiers, validation pipelines, save migrations.

```csharp
public interface IHandler<T> { bool Handle(T request); }

public sealed class HandlerChain<T>
{
    private readonly IReadOnlyList<IHandler<T>> _handlers;
    public HandlerChain(IEnumerable<IHandler<T>> handlers) => _handlers = handlers.ToArray();
    public bool Handle(T request)
    {
        foreach (var h in _handlers) if (h.Handle(request)) return true;
        return false;
    }
}
```

- Inject handlers as `IEnumerable<IHandler<T>>` via the container — order matters, so register explicitly.

### Orchestrator

Use when one use-case coordinates 3+ services. Sits in the Application layer.

```csharp
public sealed class StartLevelOrchestrator
{
    private readonly ISaveStore _save;
    private readonly ILevelLoader _loader;
    private readonly IAnalytics _analytics;
    // constructor injection

    public async UniTask ExecuteAsync(int levelId, CancellationToken ct)
    {
        var save = await _save.LoadAsync(ct);
        await _loader.LoadAsync(levelId, ct);
        _analytics.Track("level_started", levelId);
    }
}
```

- Orchestrators are async (`UniTask`, the project default), cancellation-aware, and contain no `UnityEngine` calls — they call interfaces only.
- The Presentation layer (a MonoBehaviour) gets the orchestrator injected and calls `ExecuteAsync` from a button handler.

## ScriptableObject configs

- One `ScriptableObject` type per config concern (`MovementConfig`, `AudioConfig`).
- Configs are **data**, not behavior. No `Update`-like methods.
- Reference configs through interfaces (`IMovementConfig`) for testability when the consuming code is in Domain/Application.

## Anti-patterns

- `static Instance` singletons — replace with DI registration.
- `MonoBehaviour` that owns both rendering and game logic — split into a view (MonoBehaviour) and a presenter (plain C#).
- `Update` methods that call services through `FindObjectOfType` — inject instead.
- "Manager" classes with 500+ lines — split by use-case (orchestrator per use-case).

## Verification checklist

- [ ] Domain layer compiles without `UnityEngine`.
- [ ] No new `static Instance` or service locator added.
- [ ] DI registrations match the detected container (Zenject **or** VContainer, never both).
- [ ] Each new use-case has an orchestrator class, not logic inlined into a MonoBehaviour.
- [ ] State enums with more than two values were replaced by an `IState` hierarchy.