---
name: unity-dotween
description: Animate values, transforms, UI, and TMP text with DOTween Pro — shortcut tweens (`DOMove`, `DOFade`, `DOText`), sequences, easing, lifecycle (`SetLink`, `Kill`), UniTask integration (`ToUniTask`), and the visual `DOTweenAnimation` component. Use whenever a value needs to animate over time; replaces hand-rolled coroutines that lerp values frame-by-frame.
---

# DOTween Pro

DOTween Pro is the default tween engine in this user's projects. Use shortcut tweens over hand-rolled lerps; use the Pro-only TMP/visual features where they exist.

Pair with [[unity-conventions]] (UniTask default — tweens await via `ToUniTask`), [[unity-architecture]] (animation triggers belong to Presentation; orchestrators await but don't construct tweens themselves), and [[unity-performance]] (pool / link tweens, don't allocate per frame).

## Detect first

- `Assets/Plugins/Demigiant/` (DOTween folder) and the `DOTweenPro/` subfolder under it — confirms **Pro** vs free.
- `DOTween.dll` + `DOTweenPro.dll` (or compiled-from-source) in `Assets/Plugins/Demigiant/`.
- `Assets/Resources/DOTweenSettings.asset` — global capacity / safety mode settings.
- `Packages/manifest.json` for `com.demigiant.dotween` (if installed via UPM mirror) or treat as in-`Assets` plugin otherwise.
- UniTask DOTween integration: the `UniTask.DOTween` assembly (namespace stays `Cysharp.Threading.Tasks`) — gives you `tween.ToUniTask(cancellationToken: ct)`. Expect it to be present alongside UniTask.

If DOTween is present but **not** the Pro version (no `DOTweenPro/` folder), don't write code that uses Pro-only features (`DOText` on TMP, `DOTweenAnimation` visual sequences, path editor). Ask before promoting a Pro feature.

## Initialization

- `DOTween.Init()` runs automatically on first use, but explicit init at boot is preferred so capacity warnings surface early:

```csharp
DOTween.Init(useSafeMode: true, logBehaviour: LogBehaviour.ErrorsOnly);
DOTween.SetTweensCapacity(tweenersCapacity: 500, sequencesCapacity: 50);
```

- Tune capacity to peak concurrent tweens. Going over capacity reallocates pools and stutters; set ceiling explicitly.
- `useSafeMode: true` in development (catches null-target tweens), can be `false` in shipping if profiling shows it matters.

## Shortcut tweens (the 80%)

```csharp
transform.DOMove(target, duration: 0.5f).SetEase(Ease.OutCubic);
canvasGroup.DOFade(endValue: 0f, 0.25f).OnComplete(() => gameObject.SetActive(false));
image.DOColor(Color.red, 0.2f).SetLoops(2, LoopType.Yoyo);
rectTransform.DOAnchorPosY(120f, 0.3f).SetEase(Ease.OutBack);
```

Prefer shortcut methods over `DOTween.To(...)` unless animating a custom value. Targets are automatically registered, so `DOTween.Kill(transform)` cleans them up.

### TMP (Pro only)

```csharp
_text.DOText("Hello, world!", duration: 1f, scrambleMode: ScrambleMode.None);
_text.DOFade(endValue: 1f, 0.3f);
_text.DOColor(Color.yellow, 0.2f);
_text.DOFaceColor(Color.black, 0.2f); // outline / face / underlay variants in Pro
```

Use for damage popups, dialog typewriter effects, score tickers.

## Lifecycle — non-negotiable

Tweens hold a reference to the target. If the GameObject is destroyed mid-tween and the tween isn't killed, `OnUpdate` / `OnComplete` callbacks fire on a dead target — best case `MissingReferenceException`, worst case stale state writes.

Two acceptable patterns:

### 1. `SetLink` (preferred, one-liner)

```csharp
transform.DOMove(target, 0.5f)
    .SetEase(Ease.OutCubic)
    .SetLink(gameObject, LinkBehaviour.KillOnDestroy);
```

`SetLink` auto-kills the tween when the linked GameObject is destroyed. Default behavior; use `KillOnDisable` for pooled objects.

### 2. Explicit kill in `OnDisable` / `OnDestroy`

```csharp
private Tween _moveTween;

private void Move()
{
    _moveTween?.Kill();
    _moveTween = transform.DOMove(target, 0.5f);
}

private void OnDisable() => _moveTween?.Kill();
```

Use when the same tween reference is reassigned (movement that restarts on input).

### `Kill` cleanup at scope boundaries

- Scene unload: `DOTween.KillAll();` (heavy hammer — use for hard transitions only).
- Per-target: `transform.DOKill();` — kills all tweens on that target.

## Sequences

For coordinated multi-step animations:

```csharp
var seq = DOTween.Sequence()
    .Append(transform.DOMoveY(2f, 0.4f).SetEase(Ease.OutQuad))
    .AppendInterval(0.1f)
    .Append(transform.DOScale(1.2f, 0.2f).SetEase(Ease.OutBack))
    .Join(_sprite.DOColor(Color.white, 0.2f)) // runs in parallel with the previous Append
    .OnComplete(() => _done = true)
    .SetLink(gameObject);
```

- `Append` runs after; `Join` runs parallel to the previous element; `Insert(timeOffset, ...)` for arbitrary timing.
- Build sequences in setup methods, not in `Update`. If a sequence needs to repeat, store the reference and call `Restart()` instead of rebuilding.

## Awaiting tweens (UniTask)

```csharp
public async UniTask FadeOutAsync(CancellationToken ct)
{
    await canvasGroup.DOFade(0f, 0.3f)
        .SetLink(gameObject)
        .ToUniTask(cancellationToken: ct);
    gameObject.SetActive(false);
}
```

- Always pass a `CancellationToken`. When the token fires, the tween is killed automatically.
- For sequences: `await seq.ToUniTask(cancellationToken: ct)`.
- For "wait until this specific tween point": `tween.ToUniTask(TweenCancelBehaviour.Kill, ct)` — first arg controls what happens to the tween on cancel (`Kill`, `Complete`, `Pause`).
- Don't use `yield return tween.WaitForCompletion()` in new code — UniTask path is the default in this user's projects.

## Visual `DOTweenAnimation` (Pro)

The Pro-only `DOTweenAnimation` MonoBehaviour exposes a tween via the inspector. Use it when:

- A designer needs to author/tweak the animation without code.
- The animation is a one-shot bound to a prefab (intro punch, hover wobble).

Avoid it when:

- The tween is parameterized at runtime (target depends on game state).
- The tween needs to be killed/replayed from code in non-obvious ways — drift between code and inspector is hard to debug.

Mixed approach is fine: use `DOTweenAnimation` for the visual layer and call `GetComponent<DOTweenAnimation>().DOPlay()` / `DORestart()` from code.

## ID-based control

For tweens you don't hold a reference to but might cancel by category:

```csharp
transform.DOMove(target, 0.5f).SetId("ui-popup");
DOTween.Kill("ui-popup"); // kill every tween tagged this way
```

Use string IDs sparingly — they're untyped. Constants on a static class beat ad-hoc literals.

## Common easings — quick guide

| Effect                  | Ease                         |
| ----------------------- | ---------------------------- |
| UI snappy in            | `Ease.OutCubic`, `OutQuart`  |
| UI snappy out (close)   | `Ease.InCubic`               |
| Bouncy land             | `Ease.OutBack`               |
| Damped pulse            | `Ease.OutElastic`            |
| Smooth idle loop        | `Ease.InOutSine` + Yoyo loop |
| Camera shake / spring   | Use `DOShakePosition`, not a manual ease |

Custom curves: `SetEase(AnimationCurve)` for designer-authored curves.

## Performance notes

- **Don't allocate sequences/tweens in `Update`.** Create them on event, await them, or set up a `Sequence` once with `SetAutoKill(false)` and `Restart()` on subsequent triggers.
- `SetAutoKill(false)` keeps the tween alive after completion — useful for reusable tweens, but you must `Kill` manually at end of life or it leaks.
- `SetRecyclable(true)` (or globally via settings) returns completed tweens to the pool — fewer GC allocations.
- Tweens are pooled; capacity excess reallocates. Set `DOTween.SetTweensCapacity` to your peak count.
- For many simultaneous identical tweens on different targets (e.g. 100 enemies wobbling), consider one tween on a shared driver and a custom `OnUpdate` that writes to all targets — cheaper than 100 tweens.

## Anti-patterns

- Hand-rolled coroutines that `Lerp` a value over time when a `DOTween` shortcut exists.
- Tweens without `SetLink` / explicit `Kill` on MonoBehaviours that can be destroyed.
- `OnComplete(() => this.something)` without thinking about target lifetime — if `this` is destroyed, the callback still fires unless the tween is linked.
- `WaitForCompletion()` inside `async` code — use `ToUniTask`.
- Rebuilding the same `Sequence` every time it plays — `SetAutoKill(false)` + `Restart()`.
- Mixing `DOTween` and `iTween` / hand-rolled lerps for the same object — pick one.
- `DOTween.KillAll()` as a routine cleanup — it kills *every* tween in the project including UI you didn't intend to touch. Scope to a target or ID.

## Verification checklist

- [ ] Every tween created on a MonoBehaviour target uses `SetLink(gameObject)` or is explicitly killed in `OnDisable`/`OnDestroy`.
- [ ] No tween or sequence is constructed inside `Update` / `FixedUpdate`.
- [ ] `await tween.ToUniTask(cancellationToken: ct)` is used for awaited tweens — never `WaitForCompletion`.
- [ ] If the project hits `DOTween.SetTweensCapacity` warnings in logs, capacity was raised — not silenced.
- [ ] Pro-only features (`DOText`, `DOTweenAnimation`) are only used after confirming `DOTweenPro/` is present.
- [ ] `OnComplete` callbacks don't reference destroyed targets (linked or killed correctly).