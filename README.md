# Halcyon

A first-person shooter built from scratch for [BOLDBLASTER](https://github.com/samuelling/BOLDBLASTER) (the simulation testbed for an open fMRI dataset of people playing a game), designed around the models the earlier
rounds tested (see DESIGN.md). A gang holds a derelict 1960s seaside hotel; you find guests and walk
them out. Every mechanic runs inside the same fight:

- people step into the corridor every 4-10 s, in groups of 1-5, and you must decide whether to
  shoot or hold (drift diffusion, numerosity)
- each flight of stairs carries a slowly drifting ambush risk (a restless bandit for reinforcement
  learning)
- the gang opens and shuts the security doors, so routes change (map updating)
- after a pickup the power often fails, and you walk back by torchlight (path integration)
- an open atrium, a ballroom and a terrace (grid code), varied lighting and PBR materials (early
  visual models)

**Play:** `index.html` at the repo root (with GitHub Pages on, at
https://samuelling.github.io/halcyon/; locally, `python3 -m http.server` here and open
http://localhost:8000). WASD to move, mouse to look (click to lock), click
or Space to fire, R to reload, E to take a guest, Shift to run, F for the torch. On a phone: left
thumb moves, right thumb looks, plus on-screen buttons.

**Build:** `npm i three@0.187 esbuild`, then `node build.mjs` writes `index.html`.

**Bot and harness:** `harness/bot.js` defines `window.BBX(seed)` with the BOLDBLASTER harness
contract (`frame()`, `events()`); `harness/run.mjs` renders runs for BOLDBLASTER's round 11.

## Credits

- Materials, props, sky, pistol: [Poly Haven](https://polyhaven.com), CC0 (list in
  `assets/CREDITS_polyhaven.txt`)
- Characters: Soldier.glb and Michelle.glb from the three.js examples (Mixamo characters, free to
  use in games under Adobe's Mixamo terms; not CC0)
- Engine: [three.js](https://threejs.org) (MIT)
