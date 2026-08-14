# Artwork

Everything artwork-related is plumbed and waiting. **No code changes are needed to add images** — name a file per the rule below, drop it into `Shared/Artwork.xcassets`, rebuild.

Nothing here is required. Every consumer asks for an asset name, checks whether it resolves, and falls back to a glyph or emoji when it doesn't, so the app looks deliberate with zero artwork and improves one file at a time.

## Where the files go

`Shared/Artwork.xcassets` — **not** `Rerack/Assets.xcassets`.

This matters. `Shared/` is compiled into both the app and the widget extension, so an image placed there reaches both bundles. The Live Activity runs in a separate process (`RerackWidget.appex`) that can only see its own bundle: artwork in the app's catalogue is invisible to it, and the Lock Screen thumbnail would silently stay a glyph forever.

Verified by building and inspecting both compiled catalogues:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name Rerack.app -path "*Debug-iphonesimulator*" | head -1)
xcrun assetutil --info "$APP/Assets.car" | grep animal-lion
xcrun assetutil --info "$APP/PlugIns/RerackWidget.appex/Assets.car" | grep animal-lion
```

Keep `Rerack/Assets.xcassets` for app-level things only — the icon, accent colour.

## Naming rule

Names are **derived, never looked up in a table**. [`Shared/ExerciseArtwork.swift`](../Shared/ExerciseArtwork.swift) lowercases the name and replaces every run of non-alphanumeric characters with a single hyphen:

| Source | Asset name |
|---|---|
| `Incline Dumbbell Bench Press` | `exercise-incline-dumbbell-bench-press` |
| `Barbell Bench Press - Medium Grip` | `exercise-barbell-bench-press-medium-grip` |
| `African elephant` | `animal-african-elephant` |

A derived name means renaming an exercise silently drops its artwork rather than showing the wrong picture. That's the intended trade — a table of 811 entries would go stale invisibly.

[`artwork-manifest.txt`](artwork-manifest.txt) lists every name the app will ever ask for: 16 animals and all 811 exercises, regenerated from the catalogue. Match a line exactly and it works.

## The three slots

| Slot | Where it shows | Name | Fallback today |
|---|---|---|---|
| **Animal** | Share card, Animal style | `animal-<slug>` | Emoji at ~72pt |
| **Exercise thumbnail** | Lock Screen + Dynamic Island only | `exercise-<slug>` | Dumbbell SF Symbol |
| **Share background** | Share card, behind everything | *caller-supplied* | Gradient |

Two honest caveats:

**Exercise thumbnails currently render in exactly one place** — the Live Activity ([`RerackWidgetBundle.swift:196`](../RerackWidget/RerackWidgetBundle.swift:196)). The exercise library, exercise detail, and active-workout rows do not show images yet. Adding 811 files today would light up the Lock Screen and nothing else. If the library grid is where you want them, that's a small view change, not an artwork problem.

**The share background has no naming convention** — [`backgroundAssetName`](../Rerack/Features/Share/ShareCardView.swift:45) is threaded through the view but no caller ever sets it. It exists so a background can be added without touching the render path; wiring a real one means deciding what it varies by (split? muscle group? one fixed image?) and setting the parameter.

## Format

- **Vector PDF or SVG** with "Preserve Vector Data" on is easiest — one file, every scale, and the Lock Screen renders small.
- Otherwise PNG at `@1x/@2x/@3x`.
- Thumbnails render at roughly 44×44pt on the Lock Screen and 40×40pt in the expanded island, so silhouettes read better than detailed photos.
- The animal slot renders at ~120pt on a card that gets rasterised by `ImageRenderer` for Instagram — supply enough resolution for a 1080×1920 story.
- Both light and dark backgrounds occur. A single-colour silhouette with transparency survives both; a white-background JPEG will not.

## Regenerating the manifest

After adding exercises to the catalogue:

```bash
python3 - <<'PY'
import json, re
slug = lambda v: re.sub(r'[^a-z0-9]+', '-', v.lower()).strip('-')
ex = json.load(open('Rerack/Resources/ExerciseCatalog.json'))
for n in sorted({e['name'] for e in ex}):
    print('exercise-' + slug(n))
PY
```
