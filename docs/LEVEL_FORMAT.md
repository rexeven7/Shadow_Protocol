# Shadow Protocol — Level Format

Levels are plain JSON. They're built at runtime by `scripts/LevelBuilder.gd`,
which sanitizes every field (clamping ranges, dropping malformed entries) so a
slightly-imperfect or AI-generated level still loads. This makes levels a
portable, shareable, remixable artifact — the foundation for prompt-generated,
player-shared content.

## Coordinate system

A flat ground plane. `x` runs `0 → bounds[0]`, `z` runs `0 → bounds[1]`.
An outer wall is generated automatically around the bounds, so you only list
*interior* walls. Units are meters-ish; the player capsule is ~0.8 wide.

## Schema

```jsonc
{
  "schema_version": 1,
  "name": "Compound Alpha",

  // Provenance — enables sharing, attribution and "remix this prompt".
  "meta": {
    "author": "hand-authored",
    "prompt": "",          // the description used to generate this level
    "model": ""            // the model that generated it
  },

  "bounds": [40, 28],        // width (x), depth (z). Clamped 22..64 x 18..44
  "player_start": [4, 4],    // [x, z] — start in a shadowed corner
  "terminal": [20, 15.5],    // [x, z] — hack objective, usually deep/guarded
  "extraction": [37, 25],    // [x, z] — exit, far from start

  "config": { "emp_charges": 3, "hack_time": 2.6 },

  // Interior wall segments: [x1, z1, x2, z2]. LEAVE GAPS for doorways.
  "walls": [ [15, 10, 21, 10], [15, 18, 25, 18] ],

  // Pillars / crates (~1.4 units). Give shadow and break line of sight.
  "cover": [ [12, 14], [28, 8] ],

  // Ceiling lamps = lit danger zones. Leave dark corridors between them.
  "lights": [
    { "pos": [20, 14], "range": 7.5, "energy": 2.6, "color": [1.0, 0.92, 0.7] }
  ],

  // Patrols. route is a looped list of [x, z] points.
  "guards": [
    { "start": [20, 4], "route": [[12, 4], [28, 4], [28, 8], [12, 8]],
      "view_distance": 9.5, "speed": 2.4 }
  ]
}
```

## Field ranges (after sanitization)

| Field | Range / default |
|---|---|
| `bounds` | x 22–64, z 18–44 (default 40×28) |
| `lights[].range` | 3–14 (default 6.5) |
| `lights[].energy` | 0.4–4.0 (default 2.0) |
| `lights[].color` | each channel 0–1 |
| `guards[].view_distance` | 5–13 (default 9.5) |
| `guards[].speed` | 1.2–3.6 (default 2.4) |
| `config.emp_charges` | 0–9 (default 3) |
| `config.hack_time` | 0.8–8.0s (default 2.6) |

## Design guidelines (also given to the AI generator)

- Keep coordinates ~1 unit inside the bounds.
- Ensure the player can physically reach the terminal, then the extraction —
  leave doorway gaps; never fully wall off an objective.
- Lit rooms near the terminal create the core tension (sneak the patrol, EMP the
  lamp, or take the guard down).
- 2–6 guards; place patrols to threaten the routes between start → terminal →
  extraction.

## Authoring

- **By hand:** copy `levels/level_01.json`, edit, and point the game at it.
- **By AI (in-game):** click **✦ GENERATE LEVEL**, type a description; the game
  asks Claude for conforming JSON and rebuilds live. The prompt + model are
  stored in `meta`, and you can **Copy level JSON** to share it.
