---
name: unity-build
description: "Build Unity players headless — desktop targets via the bundled build-player.sh, Android/iOS and Addressables content via an -executeMethod entry point, log parsing, IL2CPP and platform-module gotchas. Use whenever verifying that the project actually builds (not just compiles or passes tests), preparing a release build, or wiring build steps into CI."
---

# Unity Build (headless)

The verification ladder for a change: compiles (`compile-check.sh`, [[unity-conventions]]) → tests green (`run-tests.sh`, [[unity-testing]]) → **builds**. A project can pass the first two and still fail the third (player-only code paths, stripping, missing platform modules, Addressables content). Run a build before declaring release-affecting work done.

## Detect first

- `ProjectSettings/ProjectVersion.txt` → editor version (drives tool discovery).
- `ProjectSettings/EditorBuildSettings.asset` → the scene list that ships; a build with zero enabled scenes is almost always a misconfiguration.
- `Packages/manifest.json` → `com.unity.addressables` means content must be built before the player ([[unity-addressables]]).
- Existing build entry points: grep `Assets/**/Editor/**` for `BuildPipeline.BuildPlayer` / `BuildPlayerOptions` — reuse the project's own entry point instead of inventing a second one.
- Installed platform modules: a build for a target whose module isn't installed fails early with a clear log line — that's a Unity Hub installation task for the user, not something to work around.

## Desktop targets — the bundled script

```sh
bash <skills>/unity-build/scripts/build-player.sh                       # host platform, Builds/<target>/
bash <skills>/unity-build/scripts/build-player.sh Win64
bash <skills>/unity-build/scripts/build-player.sh Linux64 /abs/out/Game.x86_64
```

Same conventions as `run-tests.sh`: editor discovery via `ProjectVersion.txt` + Hub paths (`UNITY_PATH` override), refuses to run while the editor has the project open, log under `Logs/`, deduplicated `error CS*` on failure, exit `0` = build succeeded.

## Android / iOS / Addressables — `-executeMethod`

Mobile targets and content builds have no single CLI flag; the canonical approach is a static editor method committed to the project:

```csharp
// Assets/Scripts/Editor/BuildEntry.cs (editor-only asmdef)
public static class BuildEntry
{
    public static void BuildAndroid()
    {
        // Addressables content first, if the project uses it
        AddressableAssetSettings.BuildPlayerContent();

        var options = new BuildPlayerOptions
        {
            scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray(),
            target = BuildTarget.Android,
            locationPathName = "Builds/Android/Game.aab",
        };
        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
            EditorApplication.Exit(1); // make the CLI exit code honest
    }
}
```

```sh
"$UNITY" -batchmode -nographics -quit -projectPath . -buildTarget Android \
    -executeMethod BuildEntry.BuildAndroid -logFile "$(pwd)/Logs/build-android.log"
```

- `EditorApplication.Exit(1)` on failure is **mandatory** — without it the process can exit `0` on a failed build.
- One `BuildEntry` per project; parameterize via environment variables read inside the method, not by multiplying methods.
- Android specifics live in `ProjectSettings` (keystore, min SDK); iOS builds produce an Xcode project — archiving/signing happens in Xcode tooling afterwards.

## Reading a failed build log

In order of likelihood:

1. `error CS` — script compile errors (player-only code: `#if !UNITY_EDITOR` paths compile here for the first time).
2. `Assets/.../X.cs: ... 'UnityEditor' could not be found` — editor code leaked into a runtime assembly; fix the asmdef, don't `#if` around it ([[unity-editor-scripting]]).
3. `Module <target> is not installed` — platform module missing in the Hub; ask the user to install it.
4. `Shader error` / pink-screen warnings — shader doesn't compile for the target API.
5. IL2CPP stage failures (`il2cpp.exe`/`Bee` errors) — usually managed-code stripping: a reflected/serialized type got stripped. Fix with `link.xml` or `[Preserve]`, not by disabling stripping globally.
6. Addressables: `Cannot recognize file type for entry` or missing-group errors — content build out of date; rebuild content before the player.

Player logs at runtime (crash diagnosis on target) — see [unity-testing/reference/unity-logs.md](../unity-testing/reference/unity-logs.md).

## Anti-patterns

- Declaring release-affecting work done after tests alone — player builds exercise stripping, `#if !UNITY_EDITOR`, and content packing that tests never touch.
- A build entry point that swallows `BuildResult.Failed` and exits `0`.
- Disabling IL2CPP stripping (`Managed Stripping Level: Disabled`) to "fix" a stripped-type crash — use `link.xml` scoped to the affected assembly.
- Building Addressables content manually in the editor "when remembered" — wire `BuildPlayerContent()` into the entry point so player and content can't desync.
- Hardcoding the editor path in CI scripts — derive it from `ProjectVersion.txt` like the bundled scripts do.

## Verification checklist

- [ ] `build-player.sh` (or the project's `-executeMethod` entry point) exits `0`.
- [ ] The build entry point calls `EditorApplication.Exit(1)` on a non-`Succeeded` result.
- [ ] Addressables projects: content build runs as part of the player build path.
- [ ] No `UnityEditor` references leaked into runtime assemblies (build would name the file).
- [ ] For IL2CPP targets: no new reflection/serialization on types without `link.xml`/`[Preserve]` coverage.
