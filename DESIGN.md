# Halcyon: design

Halcyon is a first-person shooter built backwards from BOLDBLASTER's results. Rounds 8-10 asked
how well each brain model can be recovered from an hour of someone playing a game. The lesson of
the Betamax tunnels was that **time spent on one model is borrowed from the others**: tunnels
bought navigation and lost vision and reward. So Halcyon has no separate puzzle area. Every
mechanic runs inside the same moment-to-moment fight, so each minute of play feeds every model.

## Setting

The Halcyon is a derelict 1960s seaside hotel on a cliff. Gunmen hold the guests. You clear it
floor by floor, find guests and walk them out. The building is the level: three floors around a
central atrium, a grand stair and two service stairwells, guest corridors in a loop, a ballroom,
a kitchen, a pool terrace open to the sky, and the sea beyond the windows.

## What each model needs, and the mechanic that supplies it

| Model (candidate area) | What recovery needed in rounds 8-10 | Mechanic in Halcyon |
|---|---|---|
| V1 tuning: SF, contrast, surround (V1) | Varied, textured images; time in bright, high-contrast scenes; gaze where the model thinks it is. Dim, uniform tunnels lost most of the SF signal. | Scanned PBR materials (patterned carpet, tile, wallpaper, wood, brass), every room lit differently (sun through windows, lamps, neon, flicker), outdoor terrace. Fights happen at the crosshair: targets appear near eye height in front of you, so gaze sits at screen centre more of the time. |
| Numerosity (parietal maps) | A varied number of items in view. | Groups of 1-5 people per encounter. |
| Self-motion (hMT+/MST) | Varied forward motion and turning. | Corridors, stairs, strafing in rooms, turns at every junction. |
| Striatal RPE / value learning (ventral striatum) | Outcomes that differ from expectation, spaced far enough apart for BOLD. Betamax's 38 bursts a minute were too dense; the tunnels' outcomes were too few. | **Stairwell choice as a restless bandit**: every floor change is a choice of grand stair, east or west stairwell. Each has a hidden chance of an ambush that drifts slowly; a clear stairwell often has supplies. About 2 choices a minute, each with a clear outcome a few seconds later. |
| Drift diffusion (pre-SMA / IPS) | Many decisions with graded evidence, 5-15 s apart. Bursts were too dense; friend-or-foe figures were too few. | **Shoot or hold**: every encounter is a call between gunman and guest (armed and raised vs hands up or phone, uniform vs hotel clothes) at varied distance, light and partial cover. One every 4-10 s while moving. |
| Goal distance, path vs Euclidean (hippocampus) | Goals whose route differs from the straight line. | Objectives on other floors and round corners: a guest in room 214, then out to the terrace. Floors make path and straight-line distance diverge everywhere. |
| Boundary distance (subiculum) | Walls at varied distances. | Interior rooms and corridors throughout; distance to the nearest wall is logged every frame. |
| Facing direction, grid code (RSC/SPL, EC) | Movement in every direction across open 2D space. | The atrium floor, ballroom and pool terrace are open; corridors run in four directions. |
| Event boundaries (hippocampus) | Clear transitions. | Room-to-room transitions, floor changes, objective pick-ups and hand-offs, contacts. |
| Place familiarity (hippocampus) | Many entries, many revisits at varied gaps. | A compact building visited repeatedly in different orders. |
| Map updating (hippocampus) | Changes to the layout that are met, and met again. The tunnels' cave-ins were met 6-13 times an hour. | **Security doors**: the hotel's fire doors open and lock on their own (the gang runs the system). Doors are on the corridor loop and the stairwells you use, so a changed door is met within a minute and often again. Target 60+ an hour. |
| Path integration (EC/hippocampus) | Walks in the dark from a known start back to a known place. The tunnels produced 9-18 an hour. | **Blackouts on the walk out**: after you pick up a guest the power often fails; you lead them back to the stair you came up by torchlight. Target 25+ an hour. |

## Rates to hit (per hour of play)

Shoot-or-hold calls 300+, stairwell choices 100+, door changes met 60+, homing walks 25+, objectives
30+, time in darkness under 15%, time outdoors 10-20%.

## Constraints

- Forward play only; a straightforward fight. No possession or rewind.
- One continuous loop, no menus mid-play: an endless stream of objectives.
- Everything the models need is logged every frame (position, floor, facing, visible people with
  screen position and role, distance to walls, light level, room) and as events (calls, choices,
  outcomes, door changes met, blackouts, objectives).
- Assets: CC0 (Poly Haven, ambientCG) where possible. Characters are the exception (see README).

## Round 12: the Godot build

Round 11 said the hotel worked for navigation and spatial memory and for the puzzles read from
behaviour, and that the decisions were too crowded for BOLD. The Godot build keeps the building and
the rules and changes what round 11 asked for:

| Round 11 finding | Change | Logic-only check (3 seeds x 20 min) |
|---|---|---|
| every person was a call, 2.8 s apart | a group is one call (all armed or none, one pose); one unseen group at a time; no new group within 4.5 s of a call or on the stairs | calls about 280 an hour, median gap about 10 s |
| 82 stair crossings an hour | every guest waits upstairs; every landing ends in an ambush (two gunmen ahead) or a supply crate | 110-130 an hour |
| dark 20% of the time, 18 usable homing walks | the power fails 1.5-3.5 s after a pickup (p = 0.85) and returns when you reach the flight you came by, 22 s at most | dark about 10%, 24-30 walks an hour, 15-21 reaching home |
| terrace 6% of the time | three rescues in five leave by the far end of the pool terrace | about 10% |
| low contrast range, few salient onsets | real lamps, sun, neon and shadow; groups of up to five bystanders who walk on past you once the call is over | measured in round 12's renders |

Other changes: who is armed is told by the hands alone (every role draws from one pool of avatars);
hostile groups are 1-3 strong, bystander groups 1-5; health returns after six quiet seconds, so an
hour has about 10 deaths rather than 40; the round leaves the barrel before the muzzle climbs.

The harness renders with a lighter preset than the game you play (no GI bounce, no lamp shadows or
screen-space reflections, sky ambient instead), because this machine has no GPU: about 0.3 s a frame
on a software rasteriser. On a real GPU the same command can render the full-quality game.

### What round 12 measured (12 rendered runs, one hour)

Calls 297 an hour with a 9.4 s median gap; 99 stair crossings; 23 usable homing walks; dark 11%;
terrace 13%; 6 deaths. Stairwell learning from striatal BOLD became recoverable (r 0.08 → 0.43) and
the puzzles read from behaviour improved, navigation held, but decisions from BOLD got worse
(drift-diffusion boundary 0.38 → 0.02): halving the number of calls cost more than spacing them
gained. V1 spatial-frequency recovery also fell (0.46 → 0.29) for reasons not yet tested. Next: groups
about 6 s apart, and renders with the view model hidden to see what moved spatial frequency. Full
tables are in the BOLDBLASTER README and dashboard.

## More places: the gardens and the service level

The hotel alone gives one kind of space: rooms and corridors of middling size at dusk. Two more
levels widen what an hour contains, for the eye and for the play.

| | The hotel | The gardens | The service level |
|---|---|---|---|
| Space | three floors, atrium, terrace | one open ground, 56 m square | two floors of 2 m corridors and small rooms |
| Light | dusk, lamps and neon | late-afternoon sun | cold tubes, some dead; no daylight |
| Sight lines | 5-25 m | 25-50 m | 2-15 m |
| Gunmen stop and fight at | 12 m | 17 m | 9 m, and react in half the time |
| Stairs (hidden risk) | six flights | none | four narrow flights |
| Security doors | 22 | none | 13 |
| Blackouts | after most pickups upstairs | none | after most pickups upstairs |
| Where guests wait | upstairs rooms | four pavilions | upstairs stores |

Logic-only checks (20 minutes, two seeds): the gardens give 72-75 rescues and 440-480 calls an hour
with 1.4-1.6 people in view per frame, and about three times the hotel's wrong kills (telling a
phone from a pistol at 25 m is hard); the service level gives 45-48 rescues, 90-96 stair crossings
and 36-39 walks home in the dark an hour.

A level is a page of code in `game/levelgen.gd`: rooms, edges (hedge, wall, low wall, door,
security door, window), flights, lamps, props, and a table of where you start, the ways out and
where guests wait. `Level._build_native` raises the walls, floors, ceilings and steps from that
plan. The models that need stairs or blackouts simply have no trials in the gardens.

### What round 13 measured

Pacing: a call about every 6 s (the default now) gives about 420 calls an hour. It does not by
itself recover the decision parameters from BOLD (boundary r 0.20 ± 0.15 against 0.11 ± 0.14 at
9.7 s); hours do. The first-person arms cost the V1 fit nothing; fog and bloom cost about a quarter
of the frame contrast and some of the spatial-frequency fit (peak r 0.20 with, 0.26 without, 20
minutes). `nofog=1 noglow=1` on the harness command renders without them.

After round 13 the fog density and the bloom were both halved in all three levels (hotel fog 0.0045
to 0.0022, gardens 0.003 to 0.0015, service level 0.011 to 0.0055; bloom intensity 0.55 to 0.28).
On the same four playthroughs that gives 14% more frame contrast in every band, a little under half
of what removing them gives (31-38%), and a spatial-frequency peak r of 0.22, between the two.
`fogk=2 glowk=2` restores the round 12 and 13 air for a paired render; with them the current build
matches the round 13 frames to within 2%, so the closed-hands fix is not part of the gain.

### First-person hands

The first Godot hands copied their grip from an aim clip made for another skeleton: the support hand
hung open, palm up, and the pistol floated above the shooting hand. They are now built from the
pistol's own shape (`View._grip`, `View.CURL`):

- **Grip.** The shooting hand's palm lies on the right of the grip, its fingers square to the raked grip
  and wrapped round the front strap, index finger on the trigger, thumb over the top onto the left side.
  The support hand's palm covers the left panel, its wrist low, its fingers round the front of the
  shooting fingers, its thumb forward along the frame. Finger curl is set joint by joint.
- **Reach and wrists.** The shoulders come forward towards the hands and the arm roots sit a little lower
  and further forward than a real body's (out of the camera's sight, and not when looking down), so both
  hands always reach. Each forearm rolls with its hand (`Chars.untwist_forearm`), so the wrists are not
  wrung and the skin no longer shows through the cuffs.
- **Framing.** The raked grip puts each wrist in front of its hand on the line of sight. At the hip the
  pistol therefore rides muzzle-up and leans a little left, which turns the backs of the hands to the
  eye. The arms and pistol are drawn through a narrower lens than the world (58 against 72 degrees,
  applied across the view axis only, so depth, light and the sights are untouched). Aiming zooms the
  world but not the arms; their lens widens to 78 instead.
- **Player.** The player is now Business_Male_06 in shirt sleeves (still drawn for no one else). The suit
  jacket's sleeves filled the bottom third of the frame and hid the hands at any hold.

- **Tidying.** Looking down, the body eases back up to 17 cm, so the open collar (head and neck are
  hidden) stays behind the eye and you see your shirt front and feet. When aiming, the arms' lens widens
  to 78 degrees, which slims the forearms in the V and leaves the hands visible round the sights. The
  fingers fan a little, with the little fingers curled furthest, and the support thumb lies clear along
  the frame. Your own hands and pistol use anisotropic texture filtering (sharper at a slant on a real GPU;
  the software renderer here ignores it).

Scanner frames rendered from here on show the new arms. Every round 12 and 13 frame shows the old ones.

