# Shadow Protocol

An isometric stealth game built in Godot 4.6, inspired by *Splinter Cell*. You're an
operative dropped into a guarded compound at night. Stay in the shadows, slip past or
silently neutralize the guards, hack the central data terminal, and reach the
extraction zone — without being seen.

It's a real 3D world rendered through an orthographic isometric camera, so the lighting,
shadows and vision cones are all genuine — darkness is your actual cover.

## How to run

1. Open the project in **Godot 4.6** (open `project.godot`).
2. Press **F5** (or the ▶ Play button, top-right).

## Controls

| Action | Keys |
|---|---|
| Move | **WASD** / Arrow keys (relative to the iso view) |
| Run (fast, loud, more exposed) | hold **Shift** |
| Crouch (slow, quiet, low profile) | hold **Ctrl** or **C** |
| Cycle goggles (Normal → Night Vision → Thermal) | **V** or **Tab** |
| Fire EMP (kills nearby lights for ~6s) | **G** |
| Silent takedown (from behind a guard) | **E** |
| Hack terminal (hold while standing on it) | **F** |
| Restart | **R** |

## The mission

1. **Reach the data terminal** in the central secure room and hold **F** to hack it.
2. **Get to the extraction ring** (glowing green, far NE corner) to win.
3. If any guard's **detection meter** fills completely, the mission fails.

## Create levels with AI (in-game)

Click **✦ GENERATE LEVEL** (top-right), type a description — *"a cramped server
farm with a bright central vault and four guards on overlapping patrols"* — and
the game asks Claude to design it, validates the JSON, and rebuilds the level
live. The prompt and model are saved into the level so it can be shared and
remixed; hit **Copy level JSON** to put it on your clipboard.

Requires an Anthropic API key, entered in the panel and stored locally on your
machine only (`user://settings.cfg`) — never in the project. Generated levels are
also saved to `user://generated/`.

## Levels are data

Every level is plain JSON, built at runtime by `scripts/LevelBuilder.gd`, which
sanitizes the data so imperfect or AI-generated levels still load. Hand-author by
copying `levels/level_01.json`; the full schema is in `docs/LEVEL_FORMAT.md`. Each
run tracks stats (time, times spotted, takedowns, EMP used) shown on the end
screen — the seed for leaderboards and sharing "best" levels.

## Stealth systems

- **Light & shadow** — the *Visibility* meter (bottom-left) shows how lit you are.
  In darkness you're nearly invisible; standing in a pool of light gives you away.
  Crouching lowers your profile; running spikes it. Guards see a lit, close target
  almost instantly and a shadowed, distant one barely at all.
- **Vision cones** — each guard projects a cone that turns **green → yellow → red**
  as suspicion rises. Break line of sight (duck behind a wall or pillar) to cool it
  back down before it maxes out.
- **Takedowns** — approach a guard from *behind* and the `[E]` prompt appears. One
  press drops them silently and removes them as a threat.
- **Goggles** — **Night Vision** amplifies dark areas (green phosphor); **Thermal**
  cools the world and makes guards blaze as heat signatures through the gloom.
- **EMP gadget** — 3 charges. Fire one to knock out every light near you for a few
  seconds, opening a temporary corridor of darkness across a lit room.
- **Sound** — fully synthesized at runtime (no audio files). A looping ambient drone;
  stance-based footsteps (quiet crouch, loud run); **3D positional footsteps** from
  guards that pan and fade with distance; a **heartbeat** that quickens as you're
  detected; **alert music** that swells when a guard is onto you; plus stings for
  takedowns, EMP, goggles, hacking, and mission end.

## Tips

- The terminal room is brightly lit. Either **EMP the lamp**, **take down the patrolling
  guard**, or time your hack while the guard is facing away.
- Use **Thermal** to track guards through walls before you commit to a route.
- Pillars and crates block both light and line of sight — hug them.

## Project layout

```
project.godot             # config + window/render settings (input map is built in code)
scenes/Main.tscn          # entry scene (hosts World.gd)
scripts/World.gd          # orchestrator: camera, lighting, HUD, state, vision, EMP, audio, level loading
scripts/LevelBuilder.gd   # builds a level from JSON data (+ sanitizer) — the modular building blocks
scripts/LevelGenerator.gd # in-game AI level generator (panel + Claude API + live rebuild)
scripts/Player.gd         # iso movement, stances, light-based visibility
scripts/Guard.gd          # patrols, vision cones, detection, 3D footsteps, takedown
scripts/Audio.gd          # procedural SFX + ambient/heartbeat/alert beds (synthesized at runtime)
shaders/vision.gdshader   # full-screen night-vision / thermal post-process
levels/level_01.json      # the starter level, as data
docs/LEVEL_FORMAT.md      # level JSON schema + authoring guide
```

Levels are decoupled from the engine: `World.gd` is the runtime, and level content
lives in JSON. Redesign a map by editing `levels/level_01.json` (or generating one
in-game), not by touching engine code.
