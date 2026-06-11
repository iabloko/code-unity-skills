# asmdef templates

Ready-to-paste `*.asmdef` JSON for the four standard assembly kinds. Replace `Game.Feature` with the real assembly name (file name must match the `name` field). Reference assemblies **by name** (`"references": ["UniTask"]`), not by GUID — names survive package moves and are reviewable.

## Runtime feature assembly

`Assets/Scripts/Feature/Game.Feature.asmdef`

```json
{
    "name": "Game.Feature",
    "rootNamespace": "Game.Feature",
    "references": [
        "UniTask"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": false
}
```

- Add `"Zenject"` / `"VContainer"` / `"DOTween.Modules"` / `"UniRx"` to `references` as the feature needs them — only what it actually uses.
- For a pure Domain assembly (no `UnityEngine` per [[unity-architecture]]), set `"noEngineReferences": true` — the compiler then enforces the layering rule.

## Editor-only assembly

`Assets/Scripts/Feature/Editor/Game.Feature.Editor.asmdef`

```json
{
    "name": "Game.Feature.Editor",
    "rootNamespace": "Game.Feature",
    "references": [
        "Game.Feature"
    ],
    "includePlatforms": [
        "Editor"
    ],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": false,
    "precompiledReferences": [],
    "autoReferenced": true,
    "defineConstraints": [],
    "versionDefines": [],
    "noEngineReferences": false
}
```

## EditMode tests

`Assets/Scripts/Feature/Tests/Editor/Game.Feature.Tests.Editor.asmdef`

```json
{
    "name": "Game.Feature.Tests.Editor",
    "rootNamespace": "Game.Feature.Tests",
    "references": [
        "Game.Feature",
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "UniTask"
    ],
    "includePlatforms": [
        "Editor"
    ],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": [],
    "noEngineReferences": false
}
```

## PlayMode tests

`Assets/Scripts/Feature/Tests/Runtime/Game.Feature.Tests.Runtime.asmdef`

```json
{
    "name": "Game.Feature.Tests.Runtime",
    "rootNamespace": "Game.Feature.Tests",
    "references": [
        "Game.Feature",
        "UnityEngine.TestRunner",
        "UnityEditor.TestRunner",
        "UniTask"
    ],
    "includePlatforms": [],
    "excludePlatforms": [],
    "allowUnsafeCode": false,
    "overrideReferences": true,
    "precompiledReferences": [
        "nunit.framework.dll"
    ],
    "autoReferenced": false,
    "defineConstraints": [
        "UNITY_INCLUDE_TESTS"
    ],
    "versionDefines": [],
    "noEngineReferences": false
}
```

## The gotchas these templates encode

- **`overrideReferences: true` + `"nunit.framework.dll"` in `precompiledReferences`** — without this pair, `using NUnit.Framework;` fails to resolve in test assemblies. The single most common hand-written-asmdef mistake.
- **`defineConstraints: ["UNITY_INCLUDE_TESTS"]`** — keeps test assemblies out of player builds; this is also why PlayMode tests can reference `UnityEditor.TestRunner` with empty `includePlatforms`.
- **`autoReferenced: false` on tests** — production assemblies must never accidentally reference test code.
- **File name = `name` field** — Unity tolerates a mismatch, humans don't; keep them identical.
- **Don't add a test asmdef reference to the production asmdef** — the dependency points one way: tests → production.
- After creating or editing an asmdef, run `compile-check.sh` ([[unity-conventions]]) — asmdef typos fail fast there, and the new `.meta` gets generated for committing.
