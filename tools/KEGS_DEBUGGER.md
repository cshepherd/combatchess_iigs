# KEGS Debug Socket

KEGS (Apple IIgs emulator) has been patched to expose its built-in debugger
over a localhost TCP socket. `tools/kegs_dbg.py` is a small Python client.

## Setup (one-time, already done)

The patched KEGS lives at `/Applications/Apple IIGS/kegs.1.34/`. The patch
adds:

- A `-dbgport <n>` command-line flag that opens a listening socket on
  `127.0.0.1:<n>` and boots the emulator halted.
- A line-oriented wire protocol on that socket. Every line you send is run
  through KEGS's built-in monitor-style debugger (`do_debug_cmd`). Every
  line the debugger emits — including asynchronous breakpoint-hit
  notifications — is mirrored to the socket.

Posix-only, single-client, localhost-only.

## Running KEGS for a debug session

```bash
cd "/Applications/Apple IIGS/kegs.1.34"
./KEGSMAC.app/Contents/MacOS/KEGSMAC -dbgport 6510 &
```

The emulator window will open and the IIgs will be **halted at boot**.
Nothing runs until you connect and issue `g`.

To use a different port, change `6510` on both sides. 6501 and 6502 are
already used by KEGS for emulated SCC serial ports — pick something else.

## Using the Python client

```python
from kegs_dbg import Kegs

k = Kegs(port=6510)              # connect; raises if KEGS isn't listening

print(k.regs())                  # CPU registers
print(k.read_mem(0xe1, 0, 0x1f)) # hex dump of e1/0000..001f
k.set_bp(0x00, 0xc50a)           # break on ProDOS MLI entry
k.go()                           # resume
print(k.wait_for_halt())         # blocks until a breakpoint fires
print(k.regs())                  # inspect state at the hit
k.step()                         # step one instruction
k.halt()                         # async halt of a running emulator
k.cmd("e1/0010.0020")            # send an arbitrary debugger command

k.close()                        # disconnect
```

### Client API

| Method | What it does |
|---|---|
| `Kegs(host, port, timeout)` | Connect. Defaults: `127.0.0.1`, `6510`, `5.0`s |
| `cmd(line)` | Send any debugger command, return its output text |
| `regs()` | CPU registers (PC, A, X, Y, P, S, D, B, cycle count) |
| `read_mem(bank, start, end)` | Hex dump `bank/start .. bank/end` (inclusive) |
| `set_bp(bank, addr)` | Set execution breakpoint |
| `clear_bp(bank, addr)` | Delete one breakpoint |
| `list_bps()` | Show all breakpoints |
| `go()` | Resume execution |
| `step()` | Single-step one instruction |
| `halt()` | Force the running emulator back into the debugger |
| `reset()` | Reset the IIgs |
| `wait_for_halt(timeout)` | Block until a breakpoint hit message arrives |
| `close()` | Disconnect (sends `bye`) |

### Reading the responses

Every method returns the raw text the debugger emits, with one minor
artifact: when the emulator halts at a breakpoint, the debugger's
on-screen prompt line (`> ` plus a cursor byte) leaks into the stream.
It's harmless — strip it if you need clean text. The sentinel `(kegs)\n`
marks the end of each command's response and is consumed by the client.

## Wire protocol (for writing other clients)

```
client→server:   <command>\n
server→client:   *<echoed-command>\n
                 <output lines>\n
                 (kegs)\n
```

Async events (breakpoint hits, halt notifications) arrive between
prompts without a sentinel. Two socket-level commands are intercepted
before the debugger sees them:

| Command | Effect |
|---|---|
| `halt` | Calls `set_halt(1)` to force a running emulator into the debugger |
| `bye` / `quit` | Close the client connection (does **not** quit KEGS) |

You can talk to it with `nc`:

```bash
nc 127.0.0.1 6510
```

## Apple IIgs addressing reminder

24-bit addresses are written `BB/AAAA` (bank/offset). Useful banks:

| Bank | Contents |
|---|---|
| `00`, `01` | RAM (first 128 KB) |
| `02`–`7f` | Extended RAM |
| `e0`, `e1` | "Bank 0/1" shadowed system RAM (system globals, toolbox vectors, ProDOS) |
| `f0`–`ff` | ROM ($fc–$ff is the actual 256 KB ROM) |

A few well-known entry points:

| Address | What |
|---|---|
| `00/c50a` | ProDOS MLI entry (the smartport firmware calls into here) |
| `e1/0010` | Interrupt jump table entry |
| `e1/0000`..`000f` | RESET/COP/BRK/etc. native vectors |

## Underlying debugger commands

`Kegs.cmd(line)` passes any string to KEGS's debugger verbatim. Cheat sheet:

| Command | Effect |
|---|---|
| `BB/AAAAg` | Go from `BB/AAAA` |
| `g` | Go from current PC |
| `s` | Step one instruction |
| `BB/AAAAB` | Set execution breakpoint |
| `B` | List breakpoints |
| `BB/AAAAD` | Delete one breakpoint |
| `BB/AAAA.AAAA` | View memory (hex dump) |
| `BB/AAAAL` | Disassemble at address |
| `q` or `Q` or `Ctrl-E` | Dump registers |
| `r` | Reset the machine |
| `0=m` / `1=m` | Set m bit (8/16-bit accumulator) for listings |
| `0=x` / `1=x` | Set x bit (8/16-bit index) for listings |
| `<mode>V` | XOR verbose flags (1=DISK, 2=IRQ, 4=CLK, 8=SHADOW, 0x10=IWM, 0x20=DOC, 0x40=ABD, 0x80=SCC, 0x100=TEST, 0x200=VIDEO) |
| `<mode>H` | XOR halt-on flags (1=SCAN_INT, 2=IRQ, 4=SHADOW_REG, 8=C70D_WRITES) |
| `BB/AAAA.AAAAus<file>` | Save memory range to file |
| `BB/AAAA.AAAAul<file>` | Load memory range from file |

Multi-address shorthand: after `e1/0010B`, a bare `14B` sets a second
breakpoint at `e1/0014` (the bank is remembered).

## Common recipes

**Disassemble around the current PC**
```python
pc_line = k.regs()                       # e.g. "PC=00.22b0 ..."
# parse out the PC, then:
print(k.cmd("00/22b0L"))
```

**Watch a memory location for changes**
```python
k.set_bp(0xe1, 0x0010)                   # by default breaks on execute
# For read/write watchpoints, KEGS' built-in `B` is execute-only.
# Use the verbose flag for a coarser trace, or add a more specific
# debug pattern to the C source.
```

**Walk through a routine**
```python
k.set_bp(0x00, 0xc50a)
k.go()
k.wait_for_halt()
for _ in range(20):
    print(k.step())
```

**Dump a sprite buffer**
```python
print(k.read_mem(0x02, 0x2000, 0x21ff))
```

## Troubleshooting

- **`ConnectionRefusedError`** — KEGS isn't running or wasn't started
  with `-dbgport`. The flag is positional, not part of `config.kegs`.
- **`busy, debugger already attached`** — only one client at a time.
  Disconnect the other and reconnect.
- **No prompt appears / hang** — the emulator is mid-frame; default
  timeout is 5 s. If you sent `g`, the emulator is running normally
  and won't prompt until a breakpoint fires — use `wait_for_halt()`
  instead of `cmd()`.
- **`bye` doesn't quit KEGS** — it only closes the socket. Use
  `kill <pid>` or close the emulator window to quit KEGS itself.

## Field notes (July 2026 mission-2 debugging)

- **Execution breakpoints do not fire for bank $1F code** (the engine
  half). The fast-path dispatch skips the breakpoint check outside
  banks $00/$E1-ish. Put the breakpoint on the bank-$00 call site
  (e.g. the `jsl scroll_up_split` in game.s) instead.
- **`wait_for_halt` false-triggers**: every debugger command response
  contains a `g_halt_sim:` line, and stale response text in the buffer
  makes `wait_for_halt()` return immediately. Match on
  `Hit breakpoint` only if you need real hits.
- **Heavy socket polling slows emulation dramatically** (each command
  steals host time from the emulator loop). A 3-4 Hz poll is fine;
  a 5+ Hz halt/read/go cycle makes the game crawl and can smear
  mid-frame state across reads (e.g. `IMAGE01_*` holding another
  sprite's values). Read `billy_sprite+0/+2` for player position, not
  `IMAGE01_XPOS/YPOS`.
- **Runbook playback** (`-playback foo.kfix`, `KEGSFIX1` format:
  `K <cycle> <a2code> <unicode> <is_up>` / `M ...` mouse) is
  deterministic against the same disk image, but a rebuild that moves
  player positions by even 1 byte desyncs position-sensitive sections
  (ladder engage windows). Re-record after gameplay-visible changes.
- **Art banks are $2000-based**: mission background banks hold SHR
  rows at `$2000 + row*160` (mirroring the $01/$E1 screen layout),
  not at $0000. The engine's row math (`utmp = $2000 + row*160`)
  is the ground truth.
- `tools/kegs_screenshot.py` renders the live SHR screen to PNG and
  dumps key game state, resolving addresses from `src/game_Output.txt`
  so it survives rebuilds.

## Field notes (September 2026 art-check harness)

- **Bank $00 execution breakpoints do fire** (e.g. `00/22E1`, the
  `jsr draw_overlay` in game_loop, hits every frame). Breakpoints set
  before boot survive. The earlier "bp never fired" symptom was the
  game never starting (see below), not the breakpoint machinery.
- **Runbooks need the boot to be cycle-identical to the recording.**
  `config.kegs` must have `s7d1 = .../out/ddiigs.po` and NO
  `g_limit_speed = 2` line (2.8 MHz). The recordings were made at the
  default 8 MHz (`g_limit_speed` 3, which KEGS omits from the file
  because it is the default); at 2.8 MHz the title's key wait is
  reached ~3.8M cycles later than the runbook's first keypress and
  the game sits on the controller menu forever. KEGS rewrites
  `config.kegs` on exit, dropping default-valued lines. Window size
  does not matter: recorded mouse coordinates are already Apple
  640x400 coordinates (`adb_update_mouse` receives scaled values).
- **Two kinds of runbook.** `mission2/22/23.kfix` play from power-on:
  space past the splash, click the P1 carousel arrow (joystick ->
  keyboard), hold open-apple (a `C` record, $80) and click START to
  jump straight to mission 2. `mission24/25/26.kfix` were recorded
  mid-game with `testfix record` and contain only mouse motion (mouse
  is the emulated joystick, `g_joystick_type = 1`), so from power-on
  they never leave the title. Chain them from the end state of a
  from-power-on runbook with `testfix play FILE` + `g`
  (`kegs_artcheck.py run --playback a.kfix b.kfix ...` does this).
- **Fast screen capture:** `e1/2000.9fffus/abs/path` writes the 32 KB
  SHR page (pixels + SCBs + palettes) to a file in one command. Paths
  must not contain spaces.
- **Frame-accurate capture point:** break at game_loop's
  `jsr draw_overlay` (after `draw_all`): the screen shows the frame
  that `world_offset` and the scroll state describe. Breaking at
  `jsr wait_for_vbl` instead reads state one frame ahead of pixels.
- Playfield rows 188-199 are the score strip, not background.
- `tools/kegs_artcheck.py` — background-art alignment checker (see
  its docstring): `now` (one live frame), `run --playback ...`
  (per-frame breakpoint, captures on scroll-state change), `file`
  (re-check a saved capture, `--png` for an annotated image).
- `tools/kegs_bot.py` — state-driven input driver. Boots via
  `tools/boot_mission2.kfix` (the recorded title/menu sequence), then
  runs a route of steps like "hold D until abs_x >= 174", "hold W and
  require is_climbing within 20 frames, then until y == 53". Input is
  injected as generated one-key `.kfix` segments via `testfix play`,
  stopped with `testfix stop` when the goal is met. Every frame runs
  the art checker; engage steps assert ladder recognition (retrying at
  neighbouring x) and that the climb animation alternates between
  BCLIMB1/BCLIMB2. Failed steps dump a per-frame trace + PNG. A step
  the game cannot currently pass can be bridged with `bot.teleport`,
  which the report shows as SKIP. Mouse events in generated segments
  need gradual motion (the ADB mouse moves by bounded deltas), which
  is why the boot uses the recording rather than synthesized clicks.
- Debugger command latency is ~17 ms (one `run_16ms` poll per line);
  several lines sent in one write are all processed in one poll, so
  batch reads (`Session.batch`). Per-frame stepping runs ~20 f/s.
- Art-check finding kinds: OFFSET (a whole layer only matches the art
  shifted sideways), SHIFT (a column band shows the art shifted relative
  to the rest of the row — a screen drawn off the 110-byte grid),
  BLACK (columns black where the art has content — a seam gap), BAR
  (uniform rows where the art has content — an unfilled band), CORRUPT
  (wrong art rows), NOMATCH (foreign pixels: sprite remnants, text).
  The playfield's vertical view offset (screen row = art row + k) is
  inferred per layer from the longest matching band, so the "+3"
  convention after the up-split climbs needs no configuration.
- **game.s size ceiling is $BEFF** (ProDOS global page at $BF00; the
  loader silently drops bytes past it, so variables that land there
  never get their initial values and their writes corrupt ProDOS —
  the game then spins in ROM). `python3 -c "import os;print(hex(0x2000+
  os.path.getsize('out/game')))"` after every build. DEBUG_AUDIO and
  DEBUG_GOLDEN (game.s, default 0) hold ~550 bytes of dev-only code.
- `kegs_bot.py --route falltest` walks off the first platform on
  purpose and checks: a life is lost (billy_fall_count + health-bar
  segment), the respawn lands on the platform just left, a second fall
  costs another life, and with god mode ('i') a fall costs none.
- After the fall-death work game.s ends ~18 bytes under $BF00. The next
  addition needs space first: DEBUG_HELPERS=0 frees ~450 bytes.
- The bot's boot is state-driven: a breakpoint at the title's key-wait
  loop ($22B0) fires when the title is ready, then the recorded menu
  sequence in `tools/boot_mission2.kfix` plays rebased to that moment.
  A rebuild that changes disk-load time no longer desyncs it.
- Checker caveat: where two vertical layers' art nearly coincide (e.g.
  mission29 row 0 vs mission26 row 179 at the post-descent split row
  143) the layer labeling can flip and report CORRUPT for a few rows
  that are byte-exact against the right layer. Verify such reports
  with a direct row compare before treating them as defects.
- Game facts the bot relies on: WASD move, J then L within a frame =
  jump (`btn_action_jump`, JUMP_X_VEL bytes/frame while airborne);
  walking right scrolls the world in 4-byte steps once xpos >=
  SCROLL_THRESH (80) and pins xpos there; airborne x is clamped at the
  playfield edge; the position lives in both the sprite block and
  IMAGE01_XPOS/YPOS; a climb on a scrolling ladder (OP_UPSPLIT/OP_DOWN)
  advances scroll_us_off/scroll_down_off rather than ypos and may not
  set is_climbing; the level script re-arms scroll_us_enabled as soon
  as a climb ends; the player stays in the climbing state at a local
  ladder's top until a walk key is pressed; climb frames are
  BCLIMB1/2 or their DATA_MIRROR variants when facing left.

## Field notes (September 2026 mission-1 regression route)

- `kegs_bot.py --route mission1` plays mission 1 from the plain START
  (no modifier): turns on god mode ('i'), then `play_script` follows the
  level script's state machine — WAITX/WAITXREV walk to
  `script_wait_val`, WAITCLR/WAITNPC run the walk-and-punch fight loop,
  WAITUP climbs — through 6 waves, 3 ladders and Burnov to OP_END
  (~20 min; boss ~4000 frames). Art is checked every frame.
- `--attach` resumes a route on the KEGS already running (no relaunch,
  no boot). Combined with `--out DIR` it lets a stuck run be repaired by
  hand (probe, `bot.teleport`, memory writes) and continued in minutes.
- `kegs_artcheck.py dir DIR [--png] [--quiet]` re-scores every capture
  (`.bin` + `.json`) in a directory offline — for re-checking after a
  layout change in `MISSIONS`.
- `kegs_framediff.py BASE DIR...` is the model-free regression test:
  it pairs captures from two builds by engine state (world_offset,
  screen, split/descent offsets, upper row offset), masks the sprites
  and reports any background byte that differs, with PNGs. Build the
  baseline in a scratch worktree (`git worktree add ... HEAD`, copy the
  untracked build inputs, `touch src/game.s`, `make package`), swap its
  `out/ddiigs.po` and `src/game_Output.txt` into the repo for the run.
- Mission-1 art layout (checker `MISSIONS[1]`, per-screen world x):
  lower band 0..4 at 0/110/220/330/440; band A 6@278, 5@330, 7@440
  (mission17's 52 content columns sit at the file's left and the engine
  right-aligns them against screen 5); band B 9@220, 8@330, 10@440
  (mission110 is right-aligned in its file); top band 12@221, 11@331,
  13@441 (game.s `:op_up_notscr10` anchors scr12 at 221). Under the top
  band's 113 art rows the view shows the band-B layer (art rows 2..69
  at rows 115..182); after a right-scroll on the top level that lower
  strip is whatever the engine composed, which the checker cannot model
  — compare it with `kegs_framediff.py` instead.
- **Ladder engage is Y-agnostic while an OP_UP is armed** (game.s
  `:up_walk_bounds_ok`, "mission-1 style (y_top=0): engage regardless
  of Y"): any ladder x-range in `ladder_buf` engages the climb on any
  floor. A "nearest ladder" driver climbed ladder 3's range on screen 3
  and ladder 1's range on screen 8, and the up-scroll then placed the
  target art relative to the wrong spot (top level 77 bytes off-grid,
  black where scr12 should be). `INTENDED_LADDER` in kegs_bot.py maps
  OP_UP target -> ladder index (5<-0, 10<-1, 12<-2). Present in HEAD.
- **Ladder 3 assumes the view is locked at wo=296.** The script issues
  OP_SCRMIN/MAX 296 before OP_UP,12 and the up-engage centre snap
  computes xpos = 317 - wo (`sbc #3`, then the scr12 `sbc #5`). Walking
  left from screen 10 with the camera pinned at x<=30 leaves the view at
  wo=320 when Billy reaches the ladder, and pressing up snaps him to
  xpos=-3 ($FD): off-screen, climb stuck. The bot now brings the view to
  the lock first (`scroll_min_wo == scroll_max_wo`: step off the edge,
  hold the walk key until the scroll clamps), which lands Billy at x=23
  exactly as the level comments predict, and the climb then works.
- **OP_LEFT,9 used to fire 22 bytes early** (fixed Sept 2026). The
  script switched the left source to scr9 by an abs_x gate (WAITXREV
  361), satisfied at wo=352 with Billy pinned at x=6, so scr9 col 109
  landed on world 351 instead of 329 (OFFSET dx=-22 on every
  left-scroll frame). Now a second OP_LEFT while the left scroll is
  running queues the screen (`scroll_lsrc_next`); engine.s `:lcascade`
  switches bank, offset and `scroll_left_screen` exactly when the
  current source's col 0 has been used (both the split and the wide
  underflow), and mission1.s issues OP_LEFT,8 / OP_LEFT,9 back to back.
  A right-scroll screen sync drops a queued source (`:apply`).
- Screen 5's walkway rows 72..87 end at column 60 (bounds_scr5) while
  rows 60..71 run the full width: after the intended ladder-0 climb
  (x=56, y=84) a walk right stalls at world 356. The bot's WAITX/WAITXREV
  handler nudges vertically (40-frame holds — a held key only starts
  auto-repeating after ~14 frames) and keeps a direction that gains rows.
