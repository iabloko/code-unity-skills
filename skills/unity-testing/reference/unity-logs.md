# Unity logs — where they are and what to grep

When a headless run produces no results XML, or a player crashes on target, the log is the only witness. The bundled scripts (`run-tests.sh`, `compile-check.sh`, `build-player.sh`) always pass `-logFile` explicitly, so their logs land in `TestResults/` or `Logs/` inside the project — start there. This guide covers the *default* locations for everything else.

## Editor logs

Written by the editor (GUI or batchmode without `-logFile`). Overwritten per session; the previous session survives as `Editor-prev.log`.

| OS | Path |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Unity\Editor\Editor.log` |
| macOS | `~/Library/Logs/Unity/Editor.log` |
| Linux | `~/.config/unity3d/Editor.log` |

`-logFile -` streams the log to stdout instead — useful for CI runners that capture console output.

## Player logs (standalone builds)

`<CompanyName>` / `<ProductName>` come from `ProjectSettings` (Player settings). Previous run survives as `Player-prev.log`.

| OS | Path |
| --- | --- |
| Windows | `%USERPROFILE%\AppData\LocalLow\<CompanyName>\<ProductName>\Player.log` |
| macOS | `~/Library/Logs/<CompanyName>/<ProductName>/Player.log` |
| Linux | `~/.config/unity3d/<CompanyName>/<ProductName>/Player.log` |

## Mobile

- **Android** — `adb logcat -s Unity` (filters to Unity's tag); add `AndroidRuntime` for native crashes.
- **iOS** — Xcode console while attached; Console.app device logs otherwise.

## What to grep, in order of usefulness

| Pattern | Means |
| --- | --- |
| `error CS` | C# compile errors — nothing after them ran |
| `Scripts have compiler errors` | batchmode aborted before doing any work |
| `Aborting batchmode due to failure` | the batch command itself failed — read the lines above it |
| `Exception` / `NullReferenceException` | runtime failure; the stack trace follows immediately |
| `Assertion failed` | `Debug.Assert` / native assertion tripped |
| `No valid Unity Editor license` | licensing — batchmode on an unactivated machine |
| `Build completed with a result of` | player build verdict (`Succeeded` / `Failed`) |
| `Module <X> is not installed` | platform module missing in the Hub |
| `The referenced script .* is missing` | broken script reference in a scene/prefab — often `.meta`/GUID damage |
| `Shader error` | shader doesn't compile for the target |

## Habits

- Read the **first** error, not the last — Unity logs cascade; later errors are usually consequences.
- For a hung batchmode run, the log keeps growing during import — a frozen log + alive process is the thing to report, with the last lines attached.
- Don't parse logs when structured output exists: test runs have NUnit XML (`-testResults`), builds have the `BuildReport` in an `-executeMethod` entry point. Logs are the fallback, not the API.
