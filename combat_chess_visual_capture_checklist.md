# Combat Chess (Atari 8-bit) — Visual Capture & Asset-Harvest Checklist
## Reference package for the Apple IIGS port

**Status:** Capture plan / visual manifest  
**Purpose:** Build an authoritative visual reference archive before final IIGS artwork begins.

---

## 1. What We Already Have

The surviving public galleries give us four particularly useful Atari screenshots:

| Reference | What it gives us | Coverage |
|---|---|---|
| Title screen | Tank silhouette, COMBAT CHESS wordmark, Avalon Hill stripe, typography, title palette | Excellent |
| Red status screen | Large tank silhouette, STATUS lettering, roster table, SQ/GM/AM/FL presentation, clock placement | Excellent |
| Natural-terrain gameplay | Clear ground, trees, river/water, dark blocked terrain, bridges/river crossings, Red/Black unit glyphs, lower HUD | Good |
| Abstract-board gameplay | Checkerboard cells, purple special cells, Red/Black unit glyphs, lower HUD | Good |

These are sufficient to establish the broad visual language, but **not** sufficient to reconstruct all ten boards or the options/configuration screen.

---

## 2. Immediate Visual Read

### Title screen

The original title screen is visually much stronger than its technical simplicity suggests:

- huge side-view tank silhouette;
- tank body doubles as the title composition;
- blue/violet title plaque over the hull;
- white block-letter `COMBAT CHESS`;
- thin yellow horizontal divider beneath the vehicle;
- mostly neutral grey background;
- black legal/instruction text;
- extremely limited, high-contrast palette.

This should be treated as the primary aesthetic anchor for the IIGS title screen.

### Status screen

The status display continues the same military-technical language:

- enormous side-view vehicle silhouette at top;
- `STATUS` in a bright contrasting color;
- utilitarian roster beneath;
- monospaced tabular data;
- remaining player clock in the lower-left;
- repeated abbreviations `FUEL`, `AMMO`, `GAME DMG`, `SQR DMG`.

It feels more like a **1980s armored command terminal** than a conventional chess interface.

### Natural boards

The natural-terrain screenshot establishes:

- intensely bright green clear terrain;
- simple repeated pine-tree symbols;
- blue river/water;
- black or near-black impassable regions;
- compact symbolic Red/Black vehicle glyphs;
- a red lower status strip.

The artwork is symbolic rather than representational.

### Abstract boards

The abstract screenshot establishes:

- alternating light/medium grey cells;
- saturated purple special terrain;
- the same Red/Black unit glyph language;
- strong contrast with little ornamentation.

The abstract boards should therefore remain graphically distinct from the natural boards in the IIGS version.

---

## 3. Capture Rules

For every capture:

- [ ] Use an emulator with **nearest-neighbor / integer scaling**
- [ ] Disable CRT shaders, scanlines, smoothing, color bleed simulation, curvature, and overlays
- [ ] Capture losslessly as PNG
- [ ] Keep the **uncropped raw capture**
- [ ] Create a separate cropped working copy
- [ ] Preserve original palette; do not color-correct the archival copy
- [ ] Record emulator, machine type, NTSC/PAL setting, and palette preset
- [ ] Prefer NTSC unless evidence shows the published US game expected another mode
- [ ] Do not resize reference crops before measuring original pixel dimensions
- [ ] Put the cursor over an unimportant clear square when possible
- [ ] Avoid a selected unit unless that selection state is the subject being captured

Recommended filename pattern:

```text
cc_atari_<category>_<subject>_<state>_<nn>.png
```

Examples:

```text
cc_atari_title_idle_01.png
cc_atari_config_default_01.png
cc_atari_board01_start_01.png
cc_atari_unit_red_tank_idle_01.png
cc_atari_cursor_fire_01.png
```

---

# 4. Screen-Level Capture Checklist

## A. Title / Attract Mode

- [ ] **A01 — Title screen, clean idle frame**
- [ ] **A02 — Title screen after music begins**
- [ ] **A03 — Title screen immediately before transition to demo**
- [ ] **A04 — Demonstration-game transition, if visually distinct**
- [ ] **A05 — Any title-screen blink or color-cycle states**
- [ ] **A06 — Clean audio capture of one full title-theme cycle**

For title music, the capture is for:

- melody verification;
- phrase lengths;
- tempo;
- loop point;
- intro/outro structure.

The IIGS version can then receive an original Ensoniq/NinjaTracker Pro arrangement rather than trying to reproduce Atari timbres.

---

## B. Configuration / Options

The title explicitly directs the user to OPTION to view/change options, so this is an essential missing reference.

- [ ] **B01 — Configuration screen, default values**
- [ ] **B02 — Same screen with currently selected field highlighted**
- [ ] **B03 — GAME BOARD field**
- [ ] **B04 — Red unit-count selection**
- [ ] **B05 — Black unit-count selection**
- [ ] **B06 — STARTS FIRST field**
- [ ] **B07 — COMPUTER PLAYING field**
- [ ] **B08 — TIME LIMIT field**
- [ ] **B09 — MOVES PER TURN field**
- [ ] **B10 — SHOOT OPTION field**
- [ ] **B11 — Any help/instruction text shown while editing**
- [ ] **B12 — Exit/accept state**
- [ ] **B13 — Any second configuration page, if one exists**

For each field, note:

```text
screen coordinates
foreground color
background color
highlight method
increment/decrement behavior
font/case
minimum value
maximum value
wraparound behavior
```

---

## C. Army Status Displays

We already have an excellent Red status reference, but capture both sides from the same emulator session.

- [ ] **C01 — Red army status**
- [ ] **C02 — Black army status**
- [ ] **C03 — Status with full army**
- [ ] **C04 — Status after one unit is destroyed**
- [ ] **C05 — Status with partially depleted fuel/ammo**
- [ ] **C06 — Status screen transition/cycle behavior**
- [ ] **C07 — Exact clock placement and changing digits**

Record whether the large vehicle illustration changes by:

- side;
- selected/last unit;
- army composition;
- screen mode.

---

# 5. Board Capture Matrix

Capture **every board at its untouched starting state**.

| Board | Start | Empty-terrain detail | Unit placement | Special terrain | Notes |
|---|:---:|:---:|:---:|:---:|---|
| 1 | [ ] | [ ] | [ ] | [ ] | Natural |
| 2 | [ ] | [ ] | [ ] | [ ] | Natural / islands |
| 3 | [ ] | [ ] | [ ] | [ ] | Natural / river |
| 4 | [ ] | [ ] | [ ] | [ ] | Natural / central island |
| 5 | [ ] | [ ] | [ ] | [ ] | Natural |
| 6 | [ ] | [ ] | [ ] | [ ] | Abstract |
| 7 | [ ] | [ ] | [ ] | [ ] | Abstract cross |
| 8 | [ ] | [ ] | [ ] | [ ] | Smaller abstract field |
| 9 | [ ] | [ ] | [ ] | [ ] | White/grey/purple/black rules |
| 10 | [ ] | [ ] | [ ] | [ ] | Dark/night treatment |

For each board:

- [ ] Full board screenshot
- [ ] Same board with no unit selected
- [ ] Starting Red positions documented
- [ ] Starting Black positions documented
- [ ] Every terrain cell transcribed into 20×11 map data
- [ ] Palette sampled
- [ ] Terrain adjacency/orientation noted
- [ ] Bridges counted and orientations recorded
- [ ] Mountains/blocked regions recorded
- [ ] Any board-specific UI palette changes recorded

---

# 6. Natural Terrain Asset Checklist

## Clear Ground

- [ ] **T01 — Clear ground sample**
- [ ] Determine whether clear ground is:
  - flat color;
  - repeating tile;
  - patterned/dithered;
  - board-specific.

## Trees / Forest

- [ ] **T02 — Single isolated tree symbol**
- [ ] **T03 — Adjacent horizontal trees**
- [ ] **T04 — Adjacent vertical trees**
- [ ] **T05 — Dense forest block**
- [ ] **T06 — Tree next to river**
- [ ] **T07 — Tree next to mountain**
- [ ] **T08 — Tree destruction: before**
- [ ] **T09 — Tree destruction: damaged/intermediate state, if any**
- [ ] **T10 — Tree destruction: after**

Questions to resolve:

- Is every tree glyph identical?
- Does forest adjacency affect graphics?
- Is destroyed forest replaced with clear ground?

## Water / River

- [ ] **T11 — Horizontal water**
- [ ] **T12 — Vertical water**
- [ ] **T13 — Diagonal/stepped river edge**
- [ ] **T14 — Convex corner**
- [ ] **T15 — Concave corner**
- [ ] **T16 — Narrow river**
- [ ] **T17 — Broad water region**

Determine whether water is:

- a cell fill;
- an edge/shore system;
- a precomposed board graphic rather than true tiles.

## Bridges

- [ ] **T18 — Horizontal bridge**
- [ ] **T19 — Vertical bridge**
- [ ] **T20 — Any diagonal bridge**
- [ ] **T21 — Bridge + shore transition**
- [ ] **T22 — Bridge before damage**
- [ ] **T23 — Bridge after damage**
- [ ] **T24 — Bridge destroyed**
- [ ] **T25 — Bridge destroyed under/near a unit**

## Mountains / Impassable Terrain

- [ ] **T26 — Isolated mountain/blocked cell**
- [ ] **T27 — Horizontal adjacency**
- [ ] **T28 — Vertical adjacency**
- [ ] **T29 — Large blocked region**
- [ ] **T30 — Mountain next to river**
- [ ] **T31 — Mountain next to bridge**

Determine whether the dark areas seen in screenshots are literal mountain cells, a solid obstacle region, or board-background artwork.

---

# 7. Abstract Terrain Asset Checklist

## Board 6 Family

- [ ] **A6-01 — Free movement block**
- [ ] **A6-02 — Blocked movement region**
- [ ] **A6-03 — Center fire-only block**
- [ ] **A6-04 — Diagonal contact between regions**
- [ ] **A6-05 — Full Board 6 palette**

## Boards 7–8 Family

- [ ] **A78-01 — Yellow center**
- [ ] **A78-02 — Black blocked cell**
- [ ] **A78-03 — Edge/boundary treatment**
- [ ] **A78-04 — Board 7 complete**
- [ ] **A78-05 — Board 8 complete**

## Board 9 Family

- [ ] **A9-01 — White cell**
- [ ] **A9-02 — Grey destructible cell**
- [ ] **A9-03 — Grey cell damaged, if visible**
- [ ] **A9-04 — Grey cell destroyed**
- [ ] **A9-05 — Purple fire-through/no-move cell**
- [ ] **A9-06 — Black blocked cell**
- [ ] **A9-07 — Complete Board 9**

---

# 8. Unit Artwork Checklist

There are six essential faction/unit combinations.

## Red

- [ ] **U01 — Red Battle Cruiser**
- [ ] **U02 — Red Tank**
- [ ] **U03 — Red Armored Car**

## Black

- [ ] **U04 — Black Battle Cruiser**
- [ ] **U05 — Black Tank**
- [ ] **U06 — Black Armored Car**

For **each** unit:

- [ ] isolated on clear terrain
- [ ] unselected
- [ ] selected
- [ ] Move mode
- [ ] Fire mode, if unit graphic itself changes
- [ ] firing frame(s)
- [ ] hit frame(s)
- [ ] destruction frame(s)
- [ ] any blink/color-cycle
- [ ] exact sprite bounding box measured

Also determine:

- Do units have orientation?
- Does a unit face left/right depending on side?
- Does movement direction rotate or mirror it?
- Are Battle Cruiser/Tank/Armored Car genuinely different glyphs at board scale?
- Is the large status-screen tank art reused from title art or separately drawn?

---

# 9. Cursor and Interaction States

The original game conceptually has Select, Move, and Fire cursor states.

- [ ] **CUR01 — Neutral/select cursor**
- [ ] **CUR02 — Selected-unit state**
- [ ] **CUR03 — Move box**
- [ ] **CUR04 — Fire cross**
- [ ] **CUR05 — Invalid move feedback**
- [ ] **CUR06 — Invalid fire feedback**
- [ ] **CUR07 — Target-confirm state**
- [ ] **CUR08 — Cursor over Red unit**
- [ ] **CUR09 — Cursor over Black unit**
- [ ] **CUR10 — Cursor over empty terrain**
- [ ] **CUR11 — Cursor over blocked terrain**
- [ ] **CUR12 — Cursor animation/blink sequence**

Capture cursor graphics over both light and dark cells so transparency/XOR/color behavior is obvious.

---

# 10. HUD / Status-Line Elements

The gameplay screenshot already establishes the lower information strip, but capture deliberately.

- [ ] **H01 — Red player's lower HUD**
- [ ] **H02 — Black player's lower HUD**
- [ ] **H03 — `MM:SS` clock digits**
- [ ] **H04 — `SQ=` label**
- [ ] **H05 — `GM=` label**
- [ ] **H06 — `AM=` label**
- [ ] **H07 — `FL=` label**
- [ ] **H08 — maximum-width numeric values**
- [ ] **H09 — projected fuel after Move cursor**
- [ ] **H10 — empty square / no-unit status**
- [ ] **H11 — damaged unit values**
- [ ] **H12 — zero ammo**
- [ ] **H13 — near-zero fuel**
- [ ] **H14 — clock under one minute**
- [ ] **H15 — clock at 00:00 / timeout**

Measure:

```text
font cell width
font cell height
baseline
line spacing
left/right margins
HUD height
field column positions
```

---

# 11. Combat and Destruction Effects

These are not needed to begin board painting, but should be harvested before the original executable is considered fully documented.

## Firing

- [ ] **FX01 — shot initiation**
- [ ] **FX02 — muzzle flash**
- [ ] **FX03 — projectile/tracer first frame**
- [ ] **FX04 — mid-flight projectile**
- [ ] **FX05 — orthogonal shot**
- [ ] **FX06 — diagonal shot**

## Hit / Miss

- [ ] **FX07 — unit hit**
- [ ] **FX08 — ground/terrain impact**
- [ ] **FX09 — visible miss**
- [ ] **FX10 — stray hit on another unit, if observable**

## Destruction

- [ ] **FX11 — unit destruction start**
- [ ] **FX12 — explosion peak**
- [ ] **FX13 — unit removed**
- [ ] **FX14 — tree destruction**
- [ ] **FX15 — bridge destruction**
- [ ] **FX16 — Board 9 grey-cell destruction**

Whenever possible, capture these as a short lossless video plus extracted individual frames.

---

# 12. Palette Capture

Do not assume colors from screenshots are exact.

For each distinct screen family:

- [ ] Title palette
- [ ] Config palette
- [ ] Status palette
- [ ] Natural-board palette
- [ ] Abstract-board palette
- [ ] Board 10 palette
- [ ] Red unit colors
- [ ] Black unit colors
- [ ] Cursor colors
- [ ] Explosion/effect colors

Store both:

```text
Atari color register/index if recoverable
captured RGB reference value
```

The Apple IIGS art can later reinterpret these colors rather than blindly copying emulator RGB.

---

# 13. Typography Capture

- [ ] Title `COMBAT CHESS`
- [ ] `AVALON HILL GAME COMPANY`
- [ ] title instructions
- [ ] copyright text
- [ ] `STATUS`
- [ ] status table headings
- [ ] options/config labels
- [ ] numeric clock digits
- [ ] gameplay status abbreviations
- [ ] victory text
- [ ] stalemate text
- [ ] surrender text
- [ ] pause text

Note which text uses:

- stock Atari character ROM;
- custom character set;
- bitmap lettering;
- inverse/highlight text.

---

# 14. Recommended Emulator Capture Session

This sequence should obtain nearly everything in one disciplined session.

### Pass 1 — Front End

1. [ ] Boot game
2. [ ] Capture title
3. [ ] Record title music loop
4. [ ] Press OPTION
5. [ ] Capture complete configuration UI
6. [ ] Exercise every config field and capture highlight states
7. [ ] Return to title

### Pass 2 — Static Boards

8. [ ] Configure human vs human
9. [ ] Select Board 1
10. [ ] Capture untouched board
11. [ ] Repeat Boards 2–10
12. [ ] Record exact starting coordinates while doing so

### Pass 3 — Units and Cursors

13. [ ] Choose a board with generous clear space
14. [ ] Capture each Red unit
15. [ ] Capture each Black unit
16. [ ] Capture select cursor
17. [ ] Capture move cursor
18. [ ] Capture fire cursor
19. [ ] Capture projected-fuel HUD

### Pass 4 — Status Screens

20. [ ] Capture Red status
21. [ ] Capture Black status
22. [ ] Damage/use fuel/ammo
23. [ ] Capture modified status values

### Pass 5 — Terrain Destruction

24. [ ] Destroy trees
25. [ ] Destroy a bridge
26. [ ] Destroy Board 9 grey terrain
27. [ ] Capture before/after and intermediate states

### Pass 6 — Effects

28. [ ] Record an orthogonal shot
29. [ ] Record a diagonal shot
30. [ ] Record hit
31. [ ] Record miss
32. [ ] Record unit destruction
33. [ ] Record Battle Cruiser destruction / victory screen

---

# 15. Reference Package Directory

Recommended project structure:

```text
reference/
  raw/
    title/
    config/
    boards/
    status/
    effects/

  crops/
    title/
    terrain/
    units/
    cursor/
    ui/
    typography/
    effects/

  maps/
    board01.txt
    board02.txt
    board03.txt
    board04.txt
    board05.txt
    board06.txt
    board07.txt
    board08.txt
    board09.txt
    board10.txt

  palette/
    title.txt
    natural.txt
    abstract.txt
    board10.txt

  audio/
    title_reference.wav

  notes/
    capture_session.md
    pixel_measurements.md
```

---

# 16. Machine-Readable Board Extraction

While capturing each board, transcribe all 220 cells.

Suggested symbols:

```text
. = clear
T = tree
~ = water
= = bridge
M = mountain / permanent blocker

w = abstract white/free
g = abstract grey/destructible
p = abstract purple/fire-through
b = abstract black/blocker

R = Red unit placeholder
B = Black unit placeholder
```

Keep terrain and units in separate layers if possible:

```text
board terrain[11][20]
unit placement list[]
```

That prevents unit start positions from contaminating terrain data.

---

# 17. First IIGS Art Decisions to Make *After* Capture

Do not finalize these until the reference package is complete:

- [ ] 320-mode versus 640-mode main board
- [ ] square/cell pixel dimensions
- [ ] full-screen board versus board + permanent side panel
- [ ] symbolic top-down vehicles versus illustrated vehicles
- [ ] whether the title preserves the giant side-profile tank
- [ ] whether status screens retain giant technical vehicle drawings
- [ ] natural terrain realism level
- [ ] abstract-board flatness
- [ ] original Red/Black palette versus richer faction palettes
- [ ] cursor language
- [ ] explosion animation scale
- [ ] typography style

---

# 18. Current Art-Direction Hypothesis

A promising direction is **not** to turn Combat Chess into a lush isometric strategy game.

The Atari original's strongest identity comes from:

- military stencil / technical-display presentation;
- giant side-profile vehicle art;
- symbolic battlefield glyphs;
- high-contrast faction colors;
- strikingly artificial abstract boards;
- terse data readouts.

For the IIGS, that suggests:

> **"What Avalon Hill might have shipped in 1989 with a dedicated IIGS art budget."**

In practice:

- preserve the top-down tactical readability;
- keep the title's giant tank composition;
- render terrain much more beautifully without making it visually noisy;
- make unit silhouettes immediately recognizable;
- use the Ensoniq heavily for atmosphere, UI sounds, weapon effects, and the new *Over Hill, Over Dale* arrangement;
- exploit IIGS color depth and animation while retaining the original game's unusually clean military-boardgame personality.

That is a stronger identity than simply making the Atari artwork "higher resolution."
