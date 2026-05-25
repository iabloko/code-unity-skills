---
name: unity-addressables
description: Load, release, and manage Unity assets through the Addressables package — `AssetReference`, async loading with UniTask, labels, instance counting, and build/catalog workflow. Use whenever loading prefabs, scenes, audio, sprites, or any asset at runtime; replaces `Resources.Load`, direct prefab `[SerializeField]` for hot-swappable content, and `SceneManager.LoadSceneAsync` for content scenes.
---

# Unity Addressables

Addressables decouple asset *references* from asset *locations*. Anything loadable should go through them; the alternatives (`Resources.Load`, baked-in `[SerializeField]` for content, ad-hoc bundle calls) all have worse memory and shipping stories.

Assume **UniTask** is available (it is the default in this user's projects). All async examples below use `UniTask`. Pair with [[unity-conventions]], [[unity-architecture]] (load handles belong in Application-layer services, not in MonoBehaviours scattered across the scene), and [[unity-performance]] (pooling, ref-counting).

## Detect first

- `Packages/manifest.json` → `com.unity.addressables`. If absent, ask before adding it (it pulls in Asset Bundles config, a `addressables_content_state.bin`, and changes the build pipeline).
- `Assets/AddressableAssetsData/` → confirms Addressables is initialized for the project.
- Existing groups: open `Window > Asset Management > Addressables > Groups` (or read `AddressableAssetsData/AssetGroups/*.asset`). Match the existing labeling and group conventions.
- UniTask: `com.cysharp.unitask` in `manifest.json`. If somehow absent in this project — ask; the user expects it.

## Reference an asset

Two ways. Pick by scenario:

| Want                                         | Use                                                                |
| -------------------------------------------- | ------------------------------------------------------------------ |
| Inspector-assigned, type-safe (one asset)    | `AssetReferenceT<T>` field on a MonoBehaviour or ScriptableObject  |
| Lookup by string key / label                 | `Addressables.LoadAssetAsync<T>("key")` / `LoadAssetsAsync<T>(label)` |

### Inspector field (preferred for known assets)

```csharp
using UnityEngine;
using UnityEngine.AddressableAssets;

public sealed class EnemySpawner : MonoBehaviour
{
    [SerializeField] private AssetReferenceGameObject _enemyPrefab;
    // assigned in the inspector from any Addressable group
}
```

`AssetReferenceT<T>` variants exist for `GameObject`, `Sprite`, `AudioClip`, `Texture2D`, custom `ScriptableObject` subclasses.

### Key / label (for data-driven loading)

```csharp
var handle = Addressables.LoadAssetsAsync<EnemyConfig>("enemies", _ => { });
var configs = await handle.ToUniTask(); // requires Cysharp.Threading.Tasks.Addressables
// ... use configs ...
Addressables.Release(handle); // release exactly once when done
```

## Load / release rules

**Every successful `LoadAssetAsync` / `InstantiateAsync` must be paired with a `Release` / `ReleaseInstance`.** Handles are ref-counted; leaking them keeps the bundle resident in memory.

Skeleton pattern for a service:

```csharp
public sealed class EnemyAssetService : IDisposable
{
    private readonly AssetReferenceGameObject _enemyRef;
    private AsyncOperationHandle<GameObject> _handle;

    public EnemyAssetService(AssetReferenceGameObject enemyRef) => _enemyRef = enemyRef;

    public async UniTask<GameObject> LoadPrefabAsync(CancellationToken ct)
    {
        if (!_handle.IsValid())
            _handle = _enemyRef.LoadAssetAsync<GameObject>();
        return await _handle.ToUniTask(cancellationToken: ct);
    }

    public void Dispose()
    {
        if (_handle.IsValid()) Addressables.Release(_handle);
    }
}
```

Wire it through the DI container ([[unity-architecture]]) with the right lifetime so `Dispose` actually runs.

### Instantiate (creates a scene object, ref-counts the underlying asset)

```csharp
var instance = await Addressables.InstantiateAsync(_enemyRef).ToUniTask(cancellationToken: ct);
// ...
Addressables.ReleaseInstance(instance); // NOT Object.Destroy — release decrements the ref-count
```

Never `Object.Destroy` an instance created by `InstantiateAsync` — use `ReleaseInstance`, otherwise the asset ref-count stays elevated and the bundle never unloads.

## Cancellation

Always pass a `CancellationToken` and respect it. For MonoBehaviour-owned loads, use `this.GetCancellationTokenOnDestroy()` (UniTask helper) or `destroyCancellationToken` (Unity ≥ 2022.2).

```csharp
private async UniTaskVoid Start()
{
    var ct = this.GetCancellationTokenOnDestroy();
    try
    {
        var prefab = await _service.LoadPrefabAsync(ct);
        // ...
    }
    catch (OperationCanceledException) { /* expected on scene unload */ }
}
```

If the token fires mid-load, release the handle in the cancellation branch.

## Scenes

```csharp
var handle = Addressables.LoadSceneAsync("Levels/Level_01", LoadSceneMode.Additive);
var sceneInstance = await handle.ToUniTask(cancellationToken: ct);
// ... later ...
await Addressables.UnloadSceneAsync(sceneInstance).ToUniTask(cancellationToken: ct);
```

`UnloadSceneAsync` decrements the handle; do not use the regular `SceneManager.UnloadSceneAsync` on an Addressable scene.

## Labels & groups

- Use labels for *runtime queries* (`LoadAssetsAsync<T>(label, ...)`); use groups for *build-time packing* (what ships together).
- Naming: kebab-case labels (`enemy-configs`, `boot-bundle`).
- `_LocalBootstrap` group with `Cannot Change Post Release` packing for first-frame content. Everything else in remote / on-demand groups.
- Catalog and bundle settings live in the group's `BundledAssetGroupSchema`. Don't hand-edit; use the Groups window.

## TMP fonts & ScriptableObject configs

TextMeshPro fonts (`TMP_FontAsset`) and game configs (`ScriptableObject`) are perfect Addressable candidates — they are referenced from many places and benefit from explicit lifetime:

```csharp
[SerializeField] private AssetReferenceT<TMP_FontAsset> _localizedFontRef;

var font = await _localizedFontRef.LoadAssetAsync<TMP_FontAsset>().ToUniTask(cancellationToken: ct);
_text.font = font;
// release when the screen unloads
```

## Build / catalog workflow

- **Build content** before a Player build: `Window > Asset Management > Addressables > Groups > Build > New Build > Default Build Script`. Output goes to `Library/com.unity.addressables/aa/<platform>/`.
- For remote content: configure `RemoteLoadPath` per profile, host catalog + bundles at a URL, and call `Addressables.UpdateCatalogs(...)` on startup.
- Commit `addressables_content_state.bin` if you ship content updates — it pins the previous build and enables `Update a Previous Build`.
- CI: run `AddressablesPlayerBuildProcessor` or call `AddressableAssetSettings.BuildPlayerContent()` from an editor script before `BuildPipeline.BuildPlayer`.

## Combining with object pooling

For prefabs spawned hundreds of times (bullets, VFX), Addressables + `UnityEngine.Pool.ObjectPool` work well together:

```csharp
public sealed class BulletPool : IDisposable
{
    private readonly AssetReferenceGameObject _ref;
    private AsyncOperationHandle<GameObject> _prefabHandle;
    private ObjectPool<GameObject> _pool;

    public async UniTask InitializeAsync(CancellationToken ct)
    {
        _prefabHandle = _ref.LoadAssetAsync<GameObject>();
        var prefab = await _prefabHandle.ToUniTask(cancellationToken: ct);
        _pool = new ObjectPool<GameObject>(
            createFunc: () => Object.Instantiate(prefab),
            actionOnGet: go => go.SetActive(true),
            actionOnRelease: go => go.SetActive(false),
            actionOnDestroy: Object.Destroy,
            defaultCapacity: 64, maxSize: 512);
    }

    public GameObject Get() => _pool.Get();
    public void Return(GameObject go) => _pool.Release(go);

    public void Dispose()
    {
        _pool?.Dispose();
        if (_prefabHandle.IsValid()) Addressables.Release(_prefabHandle);
    }
}
```

Note: instances are created with `Object.Instantiate` against a loaded prefab (cheaper than `InstantiateAsync` per bullet), and the pool destroys them with `Object.Destroy` — the *asset* handle is what gets released at shutdown.

## Anti-patterns

- Calling `LoadAssetAsync` in `Update` or in response to every keypress — caches the same asset, but the handle is still acquired on each call; either cache the handle or use `AssetReference.OperationHandle` defensively.
- `Object.Destroy` on a `GameObject` returned by `InstantiateAsync` — see "Instantiate" above.
- Forgetting to release on scene unload / game shutdown — bundles stay resident.
- Loading by string key copy-pasted from the inspector — fragile, no compile-time check. Use `AssetReference` fields.
- Mixing `Resources.Load` and Addressables for the same asset — either go through `Resources` or Addressables, not both; the asset will ship twice.
- `await Addressables.LoadAssetAsync<T>(...).Task` — uses TPL Task, ignores Unity's sync context and UniTask integration. Use `.ToUniTask(...)`.
- Putting `[SerializeField] private GameObject _prefab;` on a content prefab when the project has Addressables — defeats memory wins. Reserve direct serialized references for tiny boot-time content.

## Verification checklist

- [ ] Every `LoadAssetAsync` / `InstantiateAsync` in the change has a matching `Release` / `ReleaseInstance` on every path (success, cancel, exception).
- [ ] No new `Resources.Load*` call was introduced.
- [ ] `AssetReferenceT<T>` used in inspectors instead of string keys.
- [ ] All async loads accept a `CancellationToken` and respect it.
- [ ] Bundles / groups configured for the new asset (don't ship orphaned Addressables that never got grouped).
- [ ] Content build (`Build > New Build`) re-run before testing in a Player.