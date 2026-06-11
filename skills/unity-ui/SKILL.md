---
name: unity-ui
description: "Build uGUI interfaces — Canvas organization and rebuild cost, anchors vs LayoutGroups, raycast hygiene, passive View + Presenter wiring, CanvasGroup show/hide, list pooling, TextMeshPro usage, SpriteAtlas batching, safe area. Use whenever creating or editing UI screens, popups, HUD, or any Canvas-based prefab; assumes uGUI + TMP (detect UI Toolkit first and ask if the project uses it instead)."
---

# Unity UI (uGUI + TextMeshPro)

uGUI is the default UI system in this user's projects, with TextMeshPro for all text. The two recurring costs to design against: **canvas rebuilds** (any dirty Graphic re-meshes its whole canvas) and **layout passes** (LayoutGroups cascade). Structure first, then bind.

Pair with [[unity-conventions]] (TMP default, `[SerializeField] private`), [[unity-architecture]] (View is passive Presentation; logic lives in a plain-C# presenter), [[unity-dotween]] (UI animation), [[unity-unitask]] (async show/hide, click handlers), [[unity-unirx]] (reactive binding when present), [[unity-performance]] (profile before optimizing), and [[unity-addressables]] (screens, sprites, fonts as loadable content).

## Detect first

- `Packages/manifest.json` → `com.unity.ugui` (uGUI) — the assumed default.
- UI Toolkit signals: `*.uxml` / `*.uss` assets, `UIDocument` components, `com.unity.ui` usage. If the project's runtime UI is UI Toolkit-based, **ask** before writing uGUI code — these rules don't transfer.
- Existing UI conventions: a `UIRoot`/`ScreenManager` prefab, popup service, view base class — extend what's there instead of inventing a parallel system.
- TMP font assets and material presets — reuse existing presets; don't create new ones ad hoc.

## Canvas organization

A change to any Graphic (text, image, color, enabled state) dirties its canvas and re-generates that canvas's mesh. Contain the blast radius:

- **Split by update frequency.** Static background/frame elements on one canvas; frequently-changing elements (score, timers, bars) on their own (nested) canvas. A nested canvas isolates rebuilds from its parent.
- Don't toggle `gameObject.SetActive` on a whole canvas to hide it frequently — disable the `Canvas` component (cheap, keeps the mesh) or use a `CanvasGroup` (see below).
- One `Canvas` + `CanvasScaler` (Scale With Screen Size, one agreed reference resolution, match ≈ 0.5) at the UI root; screens are children, not separate root canvases — unless update-frequency splitting says otherwise.
- World-space canvases: assign the event camera explicitly; never resolve `Camera.main` per frame.

## Layout

- **Anchors and pivots first.** Static composition should be done with RectTransform anchoring, not LayoutGroups.
- LayoutGroup + ContentSizeFitter are for genuinely dynamic content (lists, flowing text containers). Each dirty element triggers a layout pass that cascades through nested groups — never nest LayoutGroups inside dynamic per-frame content.
- After batch-populating a layout, force one synchronous pass instead of waiting a dirty frame: `LayoutRebuilder.ForceRebuildLayoutImmediate(rect)`.
- Never animate LayoutGroup-driven properties per frame (padding, spacing, preferred size) — animate the RectTransform or a `CanvasGroup.alpha` instead; layout animation rebuilds layout every frame.

## Raycast hygiene

- `raycastTarget = false` on every decorative `Image`/`TMP_Text` — only actual click targets keep it. Default-on is the single most common uGUI waste.
- Disable the `GraphicRaycaster` on canvases with no interactive elements.
- Gate whole panels with `CanvasGroup.blocksRaycasts` rather than toggling `raycastTarget` on children.

## View / Presenter wiring

Views are passive MonoBehaviours: serialized references in, plain methods out. No game logic, no service calls, no state machines inside a view.

```csharp
public sealed class ShopItemView : MonoBehaviour
{
    [SerializeField] private TMP_Text _title;
    [SerializeField] private TMP_Text _price;
    [SerializeField] private Image _icon;
    [SerializeField] private Button _buyButton;

    public event Action BuyClicked;

    public void Set(string title, string price, Sprite icon)
    {
        _title.SetText(title);
        _price.SetText(price);
        _icon.sprite = icon;
    }

    public void SetInteractable(bool value) => _buyButton.interactable = value;

    private void OnEnable() => _buyButton.onClick.AddListener(OnBuy);
    private void OnDisable() => _buyButton.onClick.RemoveListener(OnBuy);
    private void OnBuy() => BuyClicked?.Invoke();
}
```

- The presenter (plain C#, DI-constructed — see [[unity-architecture]]) subscribes to view events, talks to services, and pushes data back via `Set*` methods.
- With UniRx in the project, replace the C# event with `ReactiveProperty` bindings per [[unity-unirx]]; the view stays passive either way.
- Subscribe in `OnEnable`, unsubscribe in `OnDisable` — pairs correctly with pooling.

## Click handlers and async

Button handlers that kick off async work go through UniTask, and the button must not be clickable twice:

```csharp
private void OnBuy() => BuyAsync(destroyCancellationToken).Forget();

private async UniTaskVoid BuyAsync(CancellationToken ct)
{
    _view.SetInteractable(false);
    try { await _shopService.PurchaseAsync(_itemId, ct); }
    finally { _view.SetInteractable(true); }
}
```

Re-enable in `finally` so failures don't brick the button. See [[unity-unitask]] for cancellation rules.

## Show / hide

- Frequent toggles (popups, tooltips, HUD elements) → `CanvasGroup`: animate `alpha`, set `interactable` + `blocksRaycasts`. Avoids the `SetActive` rebuild + `OnEnable` cascade.
- Rare full screens → `SetActive` is fine; combine with Addressables load/release for heavy screens.
- Animated transitions: `await _canvasGroup.DOFade(1f, 0.25f).SetLink(gameObject).ToUniTask(cancellationToken: ct)` — rules in [[unity-dotween]].

## Lists

- Never instantiate one cell per data item for long lists — pool cells and recycle on scroll (project's existing recycling scroll view if present; otherwise a simple pool over `ScrollRect`).
- Populate cells via the same passive-view `Set(...)` pattern; cells must be fully reset by `Set`, not rely on prefab defaults.
- For < ~20 always-visible items, plain instantiate-into-LayoutGroup is fine — don't build a recycler nobody needs (YAGNI).

## TextMeshPro

- `TMP_Text.SetText(...)` over `.text +=` / string interpolation in any repeated path; for numbers, `SetText("{0}", value)` overloads avoid `ToString` garbage.
- Don't enable Auto Size on text that changes per frame — it runs a fit loop per change. Fix the font size per design instead.
- `fontMaterial` / `material` on a TMP component **instantiates** a material copy (breaks batching, leaks until destroyed); use `fontSharedMaterial` and shared material presets for styling variants.
- Static known charsets (digits for counters, fixed labels) → static font atlases; dynamic atlases only for user-generated/localized text.

## Sprites and batching

- Group screen-cohabiting sprites into a `SpriteAtlas` — un-atlased sprites each cost a draw call.
- Draw order interleaving (image, text, image, text...) breaks batching even within one atlas; group images together and texts together in the hierarchy where the design allows.
- Diagnose with the Frame Debugger before restructuring — see [[unity-performance]].

## Safe area

Phones with notches/punch-holes need the interactive layer inside `Screen.safeArea`. One `SafeArea` RectTransform under the canvas root that all screens parent into; full-bleed backgrounds stay outside it. Reuse the project's existing helper if one exists.

## Anti-patterns

- `UnityEngine.UI.Text`, `InputField`, legacy `Outline`/`Shadow` on text — TMP equivalents only.
- Public fields for Inspector wiring — `[SerializeField] private` per [[unity-conventions]].
- View polling game state in `Update` — presenters push changes; `Update` in a view is a red flag.
- `GetComponentInChildren` / `transform.Find("...")` at runtime to locate UI elements — serialize the reference.
- Animating layout-driven properties (size, spacing) per frame.
- `raycastTarget` left on for decorative graphics.
- Per-frame `SetText` with interpolated strings, or Auto Size on dynamic text.
- One mega-canvas where a blinking timer re-meshes the entire HUD.
- A button that stays interactable while its async handler is in flight.

## Verification checklist

- [ ] No new `UnityEngine.UI.Text` — TMP everywhere.
- [ ] Every decorative Graphic added has `raycastTarget = false`.
- [ ] Frequently-updated elements sit on their own (nested) canvas, or the change is provably cheap.
- [ ] Views are passive: serialized refs + `Set*` methods + events; no service calls or game logic inside.
- [ ] Button async handlers disable the button for their duration and re-enable in `finally`.
- [ ] No LayoutGroup properties animated per frame; dynamic lists don't nest LayoutGroups.
- [ ] Long lists recycle pooled cells.
- [ ] No `fontMaterial`/`material` instantiation on TMP components — shared presets only.
- [ ] New screens respect the safe-area container.