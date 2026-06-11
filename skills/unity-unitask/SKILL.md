---
name: unity-unitask
description: "Use UniTask as the default async primitive in Unity — method signatures (`UniTask`, `UniTask<T>`, `UniTaskVoid` + `Forget()`), cancellation via `destroyCancellationToken`, PlayerLoop timing (`Yield`, `Delay`, `WaitUntil`), `WhenAll`/`WhenAny` composition, bridging coroutines and Unity async operations, and thread switching. Use whenever writing async code in a Unity project; replaces `IEnumerator` coroutines and `System.Threading.Tasks.Task` for Unity-thread work."
---

# UniTask

UniTask is the default async primitive in this user's projects. Every async API takes the shape `async UniTask FooAsync(..., CancellationToken ct)`; coroutines and `Task` are legacy interop, not defaults.

Pair with [[unity-conventions]] (naming, `Async` suffix), [[unity-architecture]] (async service APIs live in the Application layer), [[unity-dotween]] (`tween.ToUniTask`), [[unity-addressables]] (`handle.ToUniTask`), and [[unity-unirx]] (UniRx for streams, UniTask for one-shot async).

## Detect first

- `Packages/manifest.json` → `com.cysharp.unitask`. If absent, ask before introducing it — don't silently fall back to coroutines.
- Unity version (`ProjectSettings/ProjectVersion.txt`): ≥ 2022.2 has `MonoBehaviour.destroyCancellationToken` built in; older versions use UniTask's `this.GetCancellationTokenOnDestroy()`.
- Integration defines/assemblies: `UNITASK_DOTWEEN_SUPPORT` (`Cysharp.Threading.Tasks.DOTween`), Addressables and TextMeshPro integration assemblies. Expect DOTween + Addressables integrations to be present.

## Method signatures

- Returning a value of async work → `UniTask<T>`; no value → `UniTask`; fire-and-forget entry points → `async UniTaskVoid` called with `.Forget()`.
- **Never `async void`.** The only exception: handlers wired up by the Inspector (`UnityEvent`) — and even there prefer a sync wrapper that calls `.Forget()`.
- Suffix `Async`; the **last** parameter is `CancellationToken ct` (no default value in internal code — force callers to think about lifetime).

```csharp
public async UniTask<LoadResult> LoadProfileAsync(string id, CancellationToken ct)
```

## Cancellation — non-negotiable

Every await that can outlive its owner must be tied to a token.

- MonoBehaviour-owned work → `destroyCancellationToken` (Unity ≥ 2022.2) or `this.GetCancellationTokenOnDestroy()`.
- Non-MonoBehaviour owners (services, presenters) → own a `CancellationTokenSource`; `Cancel()` + `Dispose()` in the owner's teardown (`Dispose`, Zenject `IDisposable`, VContainer scope disposal).
- Combine lifetimes with `CancellationTokenSource.CreateLinkedTokenSource(ct1, ct2)` — e.g. "destroyed *or* user pressed cancel".

```csharp
private CancellationTokenSource _cts;

public void StartWork()
{
    _cts?.Cancel();
    _cts?.Dispose();
    _cts = CancellationTokenSource.CreateLinkedTokenSource(destroyCancellationToken);
    RunAsync(_cts.Token).Forget();
}
```

`OperationCanceledException` is normal control flow, **not an error**:

- Don't catch-and-log it as a failure. Catch it only to run cleanup, then rethrow or return.
- `catch (Exception)` blocks swallow it — always exclude: `catch (Exception e) when (e is not OperationCanceledException)`.
- When cancellation is an expected outcome the caller branches on: `var canceled = await task.SuppressCancellationThrow();`.

## Timing and the PlayerLoop

| Intent | Use |
| --- | --- |
| wait one frame | `await UniTask.Yield(ct)` / `UniTask.NextFrame(ct)` |
| wait N seconds (game time) | `await UniTask.Delay(TimeSpan.FromSeconds(n), cancellationToken: ct)` |
| wait N seconds (ignore pause) | `UniTask.Delay(..., DelayType.UnscaledDeltaTime, cancellationToken: ct)` |
| wait N frames | `await UniTask.DelayFrame(n, cancellationToken: ct)` |
| wait for condition | `await UniTask.WaitUntil(() => _ready, cancellationToken: ct)` |
| end of frame (capture etc.) | `await UniTask.WaitForEndOfFrame(this, ct)` |
| fixed update boundary | `await UniTask.Yield(PlayerLoopTiming.FixedUpdate, ct)` |

`PlayerLoopTiming` controls *where* in the frame a continuation runs — relevant when ordering against physics or rendering. Default `Update` is right for almost everything; don't scatter custom timings without a reason.

## Composition

```csharp
// parallel — both start immediately
var (profile, catalog) = await UniTask.WhenAll(
    LoadProfileAsync(id, ct),
    LoadCatalogAsync(ct));

// race — first one wins
int winner = await UniTask.WhenAny(
    WaitForTapAsync(ct),
    UniTask.Delay(TimeSpan.FromSeconds(5), cancellationToken: ct));
```

- Independent operations → `WhenAll`, not sequential awaits.
- A `UniTask` is a struct and can be awaited **once**. To await the same operation from several places, call `.Preserve()` first or expose a `UniTaskCompletionSource`.

`UniTaskCompletionSource<T>` is the manual signal — "await until the popup closes":

```csharp
private UniTaskCompletionSource<PopupResult> _tcs;

public UniTask<PopupResult> WaitForCloseAsync() => _tcs.Task;
private void OnConfirm() => _tcs.TrySetResult(PopupResult.Confirmed);
```

## Bridging Unity APIs

- `await SceneManager.LoadSceneAsync(...).ToUniTask(progress, cancellationToken: ct)` — but content scenes go through [[unity-addressables]].
- `await request.SendWebRequest().WithCancellation(ct)` for `UnityWebRequest`.
- `await handle.ToUniTask(cancellationToken: ct)` for Addressables `AsyncOperationHandle`.
- Progress reporting: cache the callback — `Progress.Create<float>(...)` allocates; create it once, not per call.

## Threading

Unity API is main-thread-only. For CPU-heavy work:

```csharp
await UniTask.SwitchToThreadPool();
var parsed = ParseHugeJson(raw);          // no UnityEngine.* calls here
await UniTask.SwitchToMainThread(ct);
ApplyToScene(parsed);
```

Or `await UniTask.RunOnThreadPool(() => Parse(raw), cancellationToken: ct)`. Never touch `Transform`, `GameObject`, or any `UnityEngine.Object` off the main thread.

## Coroutine migration map

| Coroutine | UniTask |
| --- | --- |
| `yield return null` | `await UniTask.Yield(ct)` |
| `yield return new WaitForSeconds(s)` | `await UniTask.Delay(TimeSpan.FromSeconds(s), cancellationToken: ct)` |
| `yield return new WaitUntil(p)` | `await UniTask.WaitUntil(p, cancellationToken: ct)` |
| `yield return new WaitForEndOfFrame()` | `await UniTask.WaitForEndOfFrame(this, ct)` |
| `yield return StartCoroutine(Other())` | `await OtherAsync(ct)` |
| `StartCoroutine(Routine())` | `RoutineAsync(ct).Forget()` |

Legacy callers that demand an `IEnumerator` can wrap: `FooAsync(ct).ToCoroutine()`. Don't write new coroutines.

## Exceptions

- `.Forget()` surfaces unhandled exceptions to `UniTaskScheduler.UnobservedTaskException` (logs by default) — that's why it beats `async void`, where exceptions crash the sync context.
- Don't let a `Forget()` chain be the only error handling for user-facing flows — top-level entry points (`async UniTaskVoid`) should try/catch and route failures to the UI/log explicitly.

## Anti-patterns

- `async void` anywhere outside Inspector-wired handlers.
- `.GetAwaiter().GetResult()`, `.Result`, `.Wait()` — deadlock under Unity's sync context. There is no sync bridge; redesign the caller.
- `Task.Run` / `Task.Delay` for Unity-thread work — wrong scheduler, allocates; use the UniTask equivalents.
- Awaiting without a `CancellationToken` in code whose owner can be destroyed — the continuation fires on a dead object.
- `catch (Exception)` that swallows `OperationCanceledException`.
- Awaiting the same `UniTask` twice without `.Preserve()` — invalid operation at best, silent corruption at worst.
- A `CancellationTokenSource` that is created per operation but never disposed, or never linked to the owner's lifetime.
- Polling flags in `Update` to sequence async steps — that's what `await` is for.

## Verification checklist

- [ ] Every `async` method returns `UniTask`/`UniTask<T>`/`UniTaskVoid` — no `async void`, no `Task` on the Unity thread.
- [ ] Every async method accepts a `CancellationToken` as its last parameter and passes it to every await inside.
- [ ] MonoBehaviour-owned work is tied to `destroyCancellationToken` / `GetCancellationTokenOnDestroy()`.
- [ ] Every `CancellationTokenSource` has an owner that cancels **and disposes** it.
- [ ] No `catch` block swallows `OperationCanceledException`.
- [ ] Independent awaits are composed with `WhenAll`, not run sequentially.
- [ ] No blocking bridges (`.Result`, `.Wait()`, `GetAwaiter().GetResult()`).
- [ ] No new `IEnumerator` coroutines where a UniTask equivalent exists.