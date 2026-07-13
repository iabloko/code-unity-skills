---
name: unity-save
description: "Persist game state — versioned `[Serializable]` save DTOs in the Domain layer, JSON serialization (JsonUtility vs Newtonsoft, pick what the project has), atomic file writes under `Application.persistentDataPath` with a backup, async IO via UniTask thread switching, ordered save migrations, and autosave timing (`OnApplicationPause`/focus loss on mobile). PlayerPrefs is for lightweight user settings only, never game state. Use whenever saving or loading progress, settings, or any data that must survive a restart."
---

# Unity Save / Persistence

A save system has three hard requirements: it never corrupts the existing save (atomic writes), it can load every version ever shipped (migrations), and it never blocks a frame (async IO). Everything else is serialization detail.

Pair with [[unity-architecture]] (the `ISaveStore` seam already used in its orchestrator examples), [[unity-unitask]] (thread switching, cancellation), [[unity-testing]] (EditMode coverage), and [[unity-input]] (binding overrides ride the same path).

## Detect first

- Existing system: grep for `persistentDataPath`, `PlayerPrefs`, `ISaveStore`, `Save`-suffixed services. **Extend what exists; never add a second save path.**
- Serializer: `com.unity.nuget.newtonsoft-json` in `manifest.json` → Newtonsoft; otherwise `JsonUtility`. Don't add Newtonsoft without asking.
- Target platform: on mobile, `OnApplicationQuit` is unreliable — `OnApplicationPause(true)` is the save point of record.

## Data model

- Save DTOs are plain `[Serializable]` classes in the **Domain** layer — no `UnityEngine.Object` fields, ever. Persist ids/keys and resolve them through configs or [[unity-addressables]] on load.
- One root type, versioned:

```csharp
[Serializable]
public sealed class SaveData
{
    public int Version = 3;
    public string ProfileId;
    public long LastPlayedUnixUtc;
    public List<LevelProgress> Levels = new();
}
```

- Timestamps as UTC (unix seconds or ISO-8601 string) — never local `DateTime.Now`, and `JsonUtility` can't serialize `DateTime` anyway.
- `JsonUtility` limits: no `Dictionary`, no polymorphism, no properties — model with lists of `[Serializable]` pairs, or use Newtonsoft if it's in the project.

## The `ISaveStore` seam

Application layer defines the interface; the file-backed implementation is an edge detail. Consumers and tests see only this:

```csharp
public interface ISaveStore
{
    UniTask<SaveData> LoadAsync(CancellationToken ct);
    UniTask SaveAsync(SaveData data, CancellationToken ct);
}
```

## Atomic write — non-negotiable

Write to a temp file, then swap; a crash mid-write must never eat the current save. Serialize off the main thread ([[unity-unitask]]); cache `persistentDataPath` on the main thread first — it isn't guaranteed off-thread-safe on all platforms.

```csharp
public sealed class FileSaveStore : ISaveStore
{
    private readonly string _path = Path.Combine(Application.persistentDataPath, "save.json");

    public async UniTask SaveAsync(SaveData data, CancellationToken ct)
    {
        await UniTask.SwitchToThreadPool();
        var json = JsonUtility.ToJson(data);
        var tmp = _path + ".tmp";
        File.WriteAllText(tmp, json);
        if (File.Exists(_path)) File.Replace(tmp, _path, _path + ".bak");
        else File.Move(tmp, _path);
        await UniTask.SwitchToMainThread(ct);
    }
}
```

`File.Replace` keeps the previous save as `.bak` — that's the corruption fallback for free.

## Load hardening

In order:

1. File missing → return a default `SaveData` (first run is not an error).
2. File present but unparsable → log the failure loudly, try `.bak`; if the backup loads, restore it as current.
3. Both corrupt → default `SaveData`, and **surface it** (log + telemetry if present) — a silent new-game on a corrupt save is masked data loss, not robustness.

## Migrations

- On load, compare `Version` against current and run migrations **in order**, each bumping by exactly one — a Chain of Responsibility ([[unity-architecture]]):

```csharp
public interface ISaveMigration
{
    int FromVersion { get; }
    void Apply(SaveData data);
}
```

- A migration is append-only history: never edit a shipped migration, never delete one while saves of that version can exist in the wild.
- Every migration gets an EditMode test loading a JSON fixture of the old shape and asserting the new one ([[unity-testing]]).

## When to save

- On meaningful transitions: level complete, purchase, settings applied.
- Mobile lifecycle: `OnApplicationPause(true)` (and `OnApplicationFocus(false)` as backup) — fire-and-forget with `.Forget()` is acceptable here since the app may be killed next.
- Never per-frame or per-value-change; if many changes cluster, mark dirty and save once on the next transition or a debounced timer.

## PlayerPrefs — the narrow lane

Only small user settings: volume, quality tier, language. Nothing that needs migration, atomicity, or backup — so never progress, inventory, currency. It writes to the registry/plist; it is not a database.

## Testing

- Consumers: inject an in-memory `ISaveStore` fake — no disk in gameplay tests.
- The store itself: EditMode tests against a temp directory (`Path.GetTempPath()`-based, cleaned in `[TearDown]`), covering the atomic-swap path, backup restore, and missing-file default.
- Migrations: one fixture per shipped version, asserting the full chain lands on the current shape.

## Anti-patterns

- `PlayerPrefs` for progress, inventory, or anything with structure.
- Synchronous `File.ReadAllText`/`WriteAllText` on the main thread during gameplay — frame hitch at best.
- Writing directly over the save file (no temp + swap) — a crash mid-write corrupts the only copy.
- An unversioned root DTO — the first schema change strands every existing player.
- Serializing MonoBehaviours/ScriptableObjects or storing `UnityEngine.Object` references in the DTO.
- Silent fallback to a new game on parse failure without trying the backup or logging.
- Saving inside `Update` or on every property change.
- Local-time timestamps.

## Verification checklist

- [ ] One save path — the change extends the existing store, no parallel system introduced.
- [ ] DTOs are Domain-layer `[Serializable]` classes with a `Version` field; no `UnityEngine.Object` inside.
- [ ] Writes are atomic (temp + swap) and keep a `.bak`; serialization happens off the main thread.
- [ ] Load handles missing / corrupt / backup / default in that order, and corruption is surfaced.
- [ ] Schema changes ship with a one-step migration plus its fixture test.
- [ ] Mobile: save wired to `OnApplicationPause(true)`.
- [ ] No new `PlayerPrefs` usage beyond simple user settings.