---
name: unity-yaml-assets
description: "Read and edit Unity's text-serialized assets — `.unity` scenes, `.prefab`, `.asset` (ScriptableObject) — directly as YAML: document anatomy (`!u!` class ids, `&fileID` anchors), reference wiring via `{fileID, guid, type}`, resolving script GUIDs through `.meta` files, safe scalar edits, and the decision ladder for when to hand-edit vs generate an editor script vs hand the task to the user in the editor. Use whenever serialized data must change without the Unity editor — wiring a `[SerializeField]` reference, tuning a ScriptableObject value, fixing a broken GUID reference."
---

# Unity YAML Assets (editing serialized data as text)

An agent works with the project on disk; the editor is often closed. C# code is only half of a Unity change — the other half lives in serialized YAML (`.unity`, `.prefab`, `.asset`). This skill covers touching that half safely. Pair with [[unity-conventions]] (`.meta` hygiene — every rule there applies here doubly), [[unity-editor-scripting]] (the editor-script alternative), and [[unity-mcp-workflow]] (doing the same through a running editor).

## Detect first

- `ProjectSettings/EditorSettings.asset` → `m_SerializationMode: 2` (Force Text). If the mode is not 2, assets may be binary — **stop and ask**; none of this applies to binary serialization.
- Confirm the target file starts with `%YAML 1.1` — a quick sanity check that it is text-serialized.
- Check whether the value you want to change is overridden by a prefab instance somewhere (grep scenes for the prefab's GUID) — editing the prefab won't change instances that override the same property.

## Decision ladder — pick the cheapest safe tier

| Change | Do |
| --- | --- |
| Scalar value in a `.asset` / `.prefab` (tune a config number, flip a bool) | **Hand-edit** the YAML |
| Wire an object/asset reference into an existing `[SerializeField]` field | **Hand-edit** — GUID from the target's `.meta` |
| Add a component, add a GameObject, restructure a prefab | **Editor script** run via `-executeMethod` ([[unity-build]] pattern) or MCP ([[unity-mcp-workflow]]) — hand-writing new engine objects (GameObject + Transform pairs, correct anchors) is error-prone |
| Scene composition, layout, anything visual | **User in the editor** — describe exactly what to place and where |

Hand-editing is for changes where the diff is a few lines and every line is verifiable by eye. Structural YAML surgery is where corrupted scenes come from.

## Document anatomy

A ScriptableObject `.asset`:

```yaml
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!114 &11400000
MonoBehaviour:
  m_ObjectHideFlags: 0
  m_Script: {fileID: 11500000, guid: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6, type: 3}
  m_Name: MovementConfig
  _maxSpeed: 7.5
  _acceleration: {x: 1, y: 0.5}
  _isGrounded: 1
```

- `--- !u!114 &11400000` — one YAML document per Unity object. `!u!114` is the **class id** (114 = MonoBehaviour/ScriptableObject); `&11400000` is the **fileID anchor**, the object's identity inside this file.
- `m_Script` points at the C# class: `fileID: 11500000` (the MonoScript main object, always this value) + the **script's GUID** + `type: 3`.
- Serialized fields appear under their exact C# field names — including the leading underscore of `_camelCase` fields.

Class ids you'll actually meet: `1` GameObject, `4` Transform, `224` RectTransform, `114` MonoBehaviour, `212` SpriteRenderer, `1001` PrefabInstance.

## References — the `{fileID, guid, type}` triple

| Form | Meaning |
| --- | --- |
| `{fileID: 0}` | null reference |
| `{fileID: 190234}` | object in the **same file** (scene-local component/GameObject) |
| `{fileID: 11400000, guid: <G>, type: 2}` | Unity-native asset in another file (`.asset`, materials) |
| `{fileID: <id>, guid: <G>, type: 3}` | imported asset (script, prefab, sprite, model sub-object) |

To wire a reference: get the GUID from the target asset's `.meta` (`guid:` line, e.g. `Grep "guid:" Assets/Configs/MovementConfig.asset.meta`), and the fileID of the object inside it (main object of a ScriptableObject asset is `11400000`; for a sprite/model sub-object, copy an existing reference to the same asset — don't guess sub-object fileIDs).

## Field names and C# changes

- **Adding** a `[SerializeField]` field in C# needs **no YAML edit** — the next import fills the default value.
- **Renaming** a C# field orphans its YAML data (silently resets to default). Use `[FormerlySerializedAs("_oldName")]` and keep it until every asset has been re-saved by the editor.
- Value encodings: `bool` → `0`/`1`, enums → their int value, `Vector2/3` → `{x: , y: , z: }`, `Color` → `{r: , g: , b: , a: }`, lists → `- item` sequences, nested `[Serializable]` classes → indented maps. Strings with special characters must be single-quoted the way Unity quotes them.

## Scenes and prefab instances

A prefab placed in a scene is a `!u!1001 PrefabInstance` whose `m_Modifications` list holds property overrides (`propertyPath` / `value` / `objectReference`). Editing an **existing** modification's `value` is safe; adding new modification entries or new stripped-object documents by hand is tier-3 territory — use an editor script.

## Editing rules

- Edit **surgically with string edits** (the Edit tool). **Never round-trip the file through a YAML parser/formatter** — Unity's YAML (custom `!u!` tags, multi-document anchors, specific quoting) does not survive generic tools, and a reformatted file is an unreviewable diff even when it loads.
- Never invent a new fileID for an engine object, never duplicate an `&` anchor within a file, never touch an existing `.meta` GUID ([[unity-conventions]]).
- Keep the diff exactly as large as the intent: one value change = one changed line.

## Verify after editing

1. `bash <skills>/unity-conventions/scripts/compile-check.sh` — any batchmode launch re-imports the edited assets; corruption surfaces in the log (`... file may be corrupted`, `Unable to parse`).
2. `bash <skills>/unity-conventions/scripts/check-meta.sh` if files were added/moved.
3. `git diff` — confirm only the intended lines changed.
4. If the editor is open, verify through MCP instead ([[unity-mcp-workflow]]): refresh, read the Console, eyeball the inspector value.

## Anti-patterns

- Round-tripping a Unity YAML file through PyYAML / `yq` / any generic YAML tool.
- Hand-building new GameObject/Transform document pairs instead of an editor script.
- Guessing a sub-object fileID (sprite in an atlas, child in a model) instead of copying a known-good reference.
- Editing the prefab when the scene instance overrides the same property — the change silently doesn't apply.
- Renaming a C# serialized field without `[FormerlySerializedAs]`.
- "Fixing" a broken reference by regenerating a `.meta` GUID — that breaks every other reference to the asset ([[unity-conventions]]).
- Declaring the edit done without an import pass — a typo'd YAML file fails only when Unity next opens it.

## Verification checklist

- [ ] Serialization mode confirmed Force Text before any hand edit.
- [ ] The change tier matches the ladder — no structural YAML written by hand.
- [ ] References use GUIDs read from the actual `.meta`, fileIDs copied from known-good usages.
- [ ] `git diff` shows only the intended lines; no reformatting noise.
- [ ] A batchmode import (`compile-check.sh`) ran clean after the edit.
- [ ] Renamed C# fields carry `[FormerlySerializedAs]`.