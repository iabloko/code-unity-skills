---
name: unity-editor-scripting
description: Write Unity Editor extensions — custom inspectors, EditorWindow, PropertyDrawer, Gizmos, asset post-processors. Detect Odin Inspector first; when present, prefer Odin attributes (`[ShowInInspector]`, `[Button]`, `[ValueDropdown]`, `OdinEditorWindow`) over hand-written `OnInspectorGUI`. Use whenever editor-side tooling is requested.
---

# Unity Editor Scripting

Editor code is a separate world from runtime code: different assembly, different platform restrictions, different APIs. Treat it as such.

Pair with [[unity-conventions]] (assembly layout) and [[unity-architecture]] (don't bleed editor code into domain).

## Detect first — Odin Inspector

Before writing any inspector / editor window, check:

1. `Packages/manifest.json` for `com.sirenix.odininspector` **or** `Assets/Plugins/Sirenix/` folder.
2. `Assets/**/*.cs` for `using Sirenix.OdinInspector;`.

**If Odin is present, it is mandatory** for serialization and editor-side logic exposure. Use it whenever a tool spec calls for inspector buttons, conditional fields, table-style lists, or runtime introspection.

If Odin is absent, fall back to plain `UnityEditor` APIs. **Do not add Odin as a dependency yourself** — ask the user first.

## With Odin (preferred path)

### Serialization & inspector exposure

- Use `[SerializeField]` for plain Unity-serializable fields (matches the rest of the codebase, no Odin tax).
- Use `[ShowInInspector]` to expose properties or non-serializable fields read-only in the inspector.
- Use `[OdinSerialize]` only when the field's type isn't Unity-serializable (dictionaries, polymorphic refs, interfaces). Be aware: forces Odin's serializer for that asset.
- Use `[HideInInspector]` + `[ShowInInspector]` to expose a property while hiding its backing field.

### Layout & conditional UI

- `[BoxGroup]`, `[FoldoutGroup]`, `[TabGroup]` — group related fields. Use sparingly; flat is fine.
- `[ShowIf]` / `[HideIf]` / `[EnableIf]` — conditional display based on another field's value. Reference fields by string name; if the name changes, the attribute silently breaks — prefer `nameof(field)`.
- `[InfoBox("...", InfoMessageType.Warning)]` — surface constraints to designers.

### Action buttons

- `[Button]` on a method exposes it as an inspector button. Prefer this over building a custom inspector when you just need "press this to do X in the editor."
- Buttons that touch scene state must call `EditorUtility.SetDirty(this)` and `Undo.RecordObject(this, "Action name")` before mutations.

### Editor windows

- Inherit from `OdinEditorWindow` for tools that mostly show one inspected object. Override `GetTarget()`.
- For tools with custom layout, fall back to `EditorWindow` + `OdinEditorWindow.InspectObject(...)` for sub-areas.

### Lists and tables

- `[TableList]` for arrays of small structs/classes (much better than the default Unity list UI).
- `[ListDrawerSettings(ShowFoldout = false, DraggableItems = true)]` to tune behavior.

### Value dropdowns

- `[ValueDropdown(nameof(GetOptions))]` for restricting to a curated set, where `GetOptions` returns `IEnumerable<ValueDropdownItem<T>>`.

## Without Odin (plain UnityEditor)

### Custom Editor

```csharp
[CustomEditor(typeof(MyComponent))]
public sealed class MyComponentEditor : Editor
{
    public override void OnInspectorGUI()
    {
        serializedObject.Update();
        EditorGUILayout.PropertyField(serializedObject.FindProperty("_speed"));
        if (GUILayout.Button("Reset")) ((MyComponent)target).Reset();
        serializedObject.ApplyModifiedProperties();
    }
}
```

- Always use `serializedObject` + `SerializedProperty` — never set field values directly through `target`, you'll lose Undo and prefab override tracking.
- Wrap mutations in `Undo.RecordObject(target, "Description")` and call `EditorUtility.SetDirty(target)`.

### PropertyDrawer

For reusing a custom UI across many fields of the same type:

```csharp
[CustomPropertyDrawer(typeof(MinMaxRange))]
public sealed class MinMaxRangeDrawer : PropertyDrawer { /* ... */ }
```

### EditorWindow

```csharp
public sealed class MyTool : EditorWindow
{
    [MenuItem("Tools/My Tool")]
    private static void Open() => GetWindow<MyTool>("My Tool");
    private void OnGUI() { /* ... */ }
}
```

### PropertyAttribute + Drawer

For lightweight reusable annotations (`[ReadOnly]`, `[Scene]`, `[Tag]`) — implement `PropertyAttribute` + matching `PropertyDrawer`.

## Common rules (Odin or not)

### Assembly placement

- All editor code lives in an assembly with an `*.asmdef` whose `includePlatforms` is `["Editor"]`.
- Runtime `*.asmdef` must **not** reference any editor assembly. Verify by trying a Player build mentally before committing.

### Conditional compilation

- Editor-only code inside a runtime file: `#if UNITY_EDITOR ... #endif`. Use sparingly; prefer to move the code into an Editor assembly.
- Inspector-only fields on a runtime `MonoBehaviour`: ok to wrap in `#if UNITY_EDITOR`.

### Asset post-processors / importers

- Subclass `AssetPostprocessor` for batch operations on imports.
- `ScriptedImporter` for custom file types.
- Be cautious: post-processors run on every import; expensive logic blocks the editor.

### Gizmos

- `OnDrawGizmos` runs every editor frame — keep it cheap, no allocations.
- `OnDrawGizmosSelected` for selection-specific overlays.

### Undo & dirty flags

Anything that mutates a scene or asset in the editor must:

1. `Undo.RecordObject(obj, "Action description");` **before** mutation.
2. Mutate.
3. `EditorUtility.SetDirty(obj);` (for assets) or `EditorSceneManager.MarkSceneDirty(scene);` (for scenes).

### Domain reload

- Static fields are wiped on script reload. Don't rely on them for editor state. Use `EditorPrefs` or a `ScriptableSingleton<T>`.

## Anti-patterns

- Writing custom `OnInspectorGUI` when Odin is present and a single `[Button]` / `[ShowIf]` would do.
- Editor code mixed into runtime MonoBehaviours without `#if UNITY_EDITOR` — breaks Player builds.
- Calling `AssetDatabase.Refresh()` on every change — expensive; batch.
- Using `target.field = x` in custom editors instead of `SerializedProperty` — breaks Undo.

## Verification checklist

- [ ] Editor file is in an `Editor/` folder with editor-only `*.asmdef`.
- [ ] Runtime assemblies have no reference to editor assemblies.
- [ ] If Odin is present, used Odin attributes instead of custom `OnInspectorGUI` where applicable.
- [ ] All mutations route through `Undo.RecordObject` + `EditorUtility.SetDirty`.
- [ ] No `AssetDatabase.SaveAssets` in a tight loop.