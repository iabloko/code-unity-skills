---
name: unity-input
description: "Handle player input through the new Input System (`com.unity.inputsystem`) — `.inputactions` assets, the generated C# wrapper vs `PlayerInput` component, callbacks vs polling, enable/disable and `Dispose` lifecycle, action-map switching per game context, interactive rebinding with persisted overrides, and `InputSystemUIInputModule` for uGUI. Detect first — check Active Input Handling; never mix legacy `Input.*` and the new system in new code. Use whenever reading player input, adding actions, or wiring input to gameplay or UI."
---

# Unity Input (new Input System)

Input is a Presentation-layer concern with a domain-facing seam: gameplay code consumes an input interface, and the Input System implementation lives at the edge ([[unity-architecture]]). The recurring failure modes are lifecycle ones — actions left enabled, callbacks never unsubscribed, rebinding operations never disposed.

Pair with [[unity-conventions]], [[unity-architecture]] (the `IInputSource` seam), [[unity-ui]] (event system module), and [[unity-save]] (persisting binding overrides).

## Detect first

- `Packages/manifest.json` → `com.unity.inputsystem`.
- `ProjectSettings/ProjectSettings.asset` → `activeInputHandler:` — `0` legacy only, `1` new only, `2` both. New code targets the new system when it's active; if the project is legacy-only, **ask** before migrating anything.
- Existing style: `Glob **/*.inputactions`, a generated wrapper class (asset's *Generate C# Class* output), `PlayerInput` components in prefabs, grep for `using UnityEngine.InputSystem;`. Match what's there — wrapper-based and `PlayerInput`-based projects wire differently.
- Never mix `Input.GetKey*`/`Input.GetAxis` with the new system in new code, even when `activeInputHandler: 2` allows it.

## Action maps — one per context

- One map per input context: `Gameplay`, `UI`, `Dialogue`, `Vehicle`. Switching context = disable one map, enable the other — **not** flag checks inside handlers of an always-on map.
- Prefer the **generated C# wrapper** (type-safe, refactor-friendly) over string lookups:

```csharp
public sealed class InputService : IInputSource, IDisposable
{
    private readonly GameInput _input = new();

     public event Action JumpPressed;

    public InputService()
    {
        _input.Gameplay.Enable();
        _input.Gameplay.Jump.performed += OnJump;
    }

    public Vector2 Move => _input.Gameplay.Move.ReadValue<Vector2>();

    public void SwitchToUI()
    {
        _input.Gameplay.Disable();
        _input.UI.Enable();
    }

    private void OnJump(InputAction.CallbackContext _) => JumpPressed?.Invoke();

    public void Dispose()
    {
        _input.Gameplay.Jump.performed -= OnJump;
        _input.Dispose();
    }
}
```

- The wrapper implements `IDisposable` — the owning service disposes it; wire that through the DI container's lifetime ([[unity-architecture]]).
- `PlayerInput` component is acceptable for prototypes and designer-wired prefabs; for anything with logic, go through a service.

## Callbacks vs polling

| Input kind | Read it via |
| --- | --- |
| Discrete (jump, fire, interact, pause) | callback: `action.performed += OnJump;` |
| Continuous (move, look, throttle) | poll: `action.ReadValue<Vector2>()` in `Update` |

- Subscribe/unsubscribe **paired**: `performed +=` in `OnEnable`/construction, `-=` in `OnDisable`/`Dispose`. Subscribe with a named method, not an inline lambda — a lambda can't be unsubscribed.
- `started` / `performed` / `canceled` map to press / trigger / release; interactions (hold, tap) shift what `performed` means — check the action's interaction before assuming.
- Read input in `Update`, apply it in `FixedUpdate` (cache the value) — polling inside `FixedUpdate` misses frames; callbacks firing physics directly bypass the fixed step.

## The architecture seam

- Application layer defines the interface (`IInputSource` with `Move`, `JumpPressed`, ...); the Input System implementation is Presentation. Gameplay and tests consume the interface — tests inject a fake and never touch a device ([[unity-testing]]).
- In ecslite projects the seam is a system: an input system polls the service and writes one-frame request components (`JumpRequest`), consumed downstream and cleaned by `DelHere<T>` ([[ecslite-systems]]).

## Rebinding

```csharp
_rebindOperation = action.PerformInteractiveRebinding()
    .WithControlsExcluding("<Mouse>/position")
    .OnComplete(op => { op.Dispose(); SaveOverrides(); })
    .OnCancel(op => op.Dispose())
    .Start();
```

- Disable the action while rebinding it; **dispose the operation** in both complete and cancel paths.
- Persist with `_input.SaveBindingOverridesAsJson()` / `LoadBindingOverridesFromJson(json)` — store the JSON through the project's save path ([[unity-save]]), not raw `PlayerPrefs` calls scattered per binding.

## UI

- The `EventSystem` needs `InputSystemUIInputModule`, not the legacy `StandaloneInputModule` — mixed modules are the classic "buttons stopped clicking" bug.
- Drive the module from the same `.inputactions` asset's `UI` map; a second asset means two devices' state fighting.

## Anti-patterns

- `Input.GetKeyDown` / `Input.GetAxis` in new code while the new system is active.
- All action maps enabled all the time, with `if (isPaused) return;` sprinkled through handlers — switch maps instead.
- `actionAsset.FindAction("Gameplay/Jump")` per frame — resolve once, cache the reference (or use the wrapper).
- Subscribing with a lambda that captures state and never unsubscribing — leaked handler firing on a dead object.
- Polling in `FixedUpdate`, or moving Rigidbodies directly from a `performed` callback.
- A rebinding operation without `Dispose` in the cancel path.
- Wrapper/`InputActionAsset` instances created per consumer — one instance per player, owned by one service.

## Verification checklist

- [ ] Active Input Handling checked; no legacy `Input.*` added alongside the new system.
- [ ] Actions grouped into per-context maps; context switches toggle maps, not flags.
- [ ] Every `performed`/`started`/`canceled` subscription has a paired unsubscription; no inline-lambda subscriptions.
- [ ] The generated wrapper (or asset) has a single owner that `Dispose`s it.
- [ ] Gameplay consumes an input interface; a fake implementation exists for tests.
- [ ] Rebinding operations disposed on complete **and** cancel; overrides persisted via the save path.
- [ ] `EventSystem` uses `InputSystemUIInputModule`.