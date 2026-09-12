# Combat Chess — Apple IIGS

A port of Avalon Hill's *Combat Chess* (Atari 8-bit, 1984) to the Apple IIGS, written in 65816 assembly with Merlin32.

The rules specification lives in `combat_chess_iigs_spec-3.md`; the plan for harvesting reference art from the original is `combat_chess_visual_capture_checklist.md`. The project follows the spec's milestones: headless rules engine, Atari verification, programmer-art debug board, final art, sound, AI.

[ cshepherd NOTE - This is major slop, but I'm releasing it because it's an interestingly near-exact port that took less than 2 days for Claude to crunch through. I was surprised by its thorough knowledge of both the Atari8 and Apple IIGS platforms ]

## Status

Current status: Playable Alpha.

Milestone 1 in progress. The disk boots into a launcher that chains a placeholder title screen and a placeholder game part. The headless rules engine is functionally complete for the printed rules: data tables, board and terrain, line tracing, units, movement, fire, turns with both Shoot Options, chess clocks with pause, and victory, time loss, surrender and stalemate, all with self-tests. Items the manual leaves open are marked UNVERIFIED in the source for milestone 2.

The ten original boards and their starting positions have been captured from the Atari game (see `reference/notes/capture_session.md`) and generated into `src/boards.s`. The game part draws any of the ten boards with the original's character set and colours (milestone 4's terrain tiles and unit glyphs, generated from the captures by `tools/gen_board_art.py`) and plays with the milestone 3 keyboard cursor and HUD. The computer plays either or both sides (the options screen's COMPUTER field): a greedy player (`src/aiplayer.s`) that advances toward the enemy Battle Cruiser and fires by expected damage, winning by destroying it. A moving unit slides square by square from its old position to its new one, and a shot flies from the attacker to its target (larger for a heavier unit) and bursts into an explosion on a hit. Arrows or WASD move the cursor, RETURN selects a friendly unit and then confirms a move or a shot (at an enemy, or at a tree, bridge or grey square to destroy it), M and F switch between move and fire (legal destinations and targets are highlighted), ESC cancels, TAB shows the army status screens (the original's SELECT: the side to move, then the opponent, then the board again; ESC also returns), E ends the turn, P pauses, X surrenders, the number keys restart on another board (0 is board 10), Q quits to the title.

The title screen carries the Atari original's tank plaque as a bitmap over QuickDraw text. RETURN begins the game and O opens the options page (the original's seven options with its exact ranges and defaults: O or down arrow moves between fields, S or right arrow steps a value, RETURN returns). The rules self-tests are an opt-in build (see [Building](#building)); when they are compiled in, a third title line appears and T runs them.

Beyond the local hot-seat game, the IIGS can play a network game against a computer opponent over an Uthernet II card — press **N** on the title. See [Network play](#network-play) below for how it works and how to stage a server locally.

## Building

Requirements:

- [Merlin32](https://github.com/lroathe/merlin32) — 65816 cross-assembler (`merlin32` on the path)
- [cadius](https://github.com/fadden/CiderPress2) — ProDOS disk image utility (`cadius` on the path)
- Python 3 — build and debugging tools

```bash
make package   # assemble everything and build out/combatchess.po
make clean     # remove out/ and the merlin32 listings
```

The rules self-tests (`src/test.s`) are excluded from the build by default. To include them, set `INCLUDE_TESTS = 1` in `src/shared.s` and rebuild: that one switch assembles the `TEST` part, adds it to the disk image, and turns on the T option on the title screen (both the source conditionals and the Makefile read that line).

The build assembles each part in `src/` with `merlin32 -V` (which also writes a `*_Output.txt` listing beside the source), creates an 800 KB ProDOS volume, and copies PRODOS plus the parts onto it through `tools/cadius_strict.sh`, a wrapper that fails the build when cadius reports an error instead of exiting zero.

## Running

Boot `out/combatchess.po` in KEGS, GSplus, or on real hardware. The volume contains only one `.SYSTEM` file, so ProDOS runs the launcher directly. A prebuilt image is committed at `out/combatchess.po` as a release artifact, so you can boot it without building (it is refreshed alongside notable changes).

`tools/kegs_run.sh` boots the image in the patched KEGS described in `tools/KEGS_DEBUGGER.md`. Add `-dbgport 6520` to open the debug socket, then `tools/kegs_screenshot.py` dumps the screen and registers.

## Network play

The IIGS can play a network game over an Uthernet II (Wiznet W5100) card: press **N** on the title. The IIGS is a thin client of an authoritative match server — it sends only validated actions (move, fire, end turn) and renders the full board the server broadcasts after each one, so it can never make an illegal move. During the connect a status log replaces the blank screen (card detected in its slot, connecting, connected, matched with the opponent, starting); if there is no card or the connection fails it prints the reason, waits for a key, and returns to the title. In play, moves and shots animate as the server's snapshots arrive, the server's clock drives the HUD, and the server decides victory. Firing works on enemy units and on trees and bridges — felling a bridge severs a river crossing.

The opponent, the server and the wire protocol are Python 3, under `server/` and `bots/`, and follow the network milestones (N1 W5100 driver, N2 binary protocol, N3 match server, N4 IIGS UI, N5 bots, N6 reconnect). The protocol (`server/protocol.py`) and the rules (`server/state.py` over `server/rules.py`, a port of the 65816 engine) are the authority; `tools/gen_fixtures.py` emits byte-exact golden frames into `server/fixtures/` that the 65816 encoder and parser are checked against, so both sides stay in lockstep.

### Staging a server locally

The IIGS connects to its **DHCP gateway on TCP port 1984**, so the match server has to run on the machine that provides the guest its network and be reachable at that address:

```bash
python3 server/match_server.py          # listens on 0.0.0.0:1984
```

Pressing N asks for a bot match, and the server spawns an opponent bot that connects back as an ordinary client. Environment variables tune it:

- `CC_BOT=greedy` uses the greedy bot (`bots/greedy_bot.py`, the network twin of `src/aiplayer.s`), `CC_BOT=chooser` the stronger search bot (`bots/chooser_bot.py`, spec 29.1: it looks a ply ahead and beats greedy roughly two to one); the default is the random bot (`bots/random_bot.py`).
- `CC_BOARD=<1..10>` picks the board (default 1; the armies engage on the more open boards 6–8).
- `CC_GRACE=<seconds>` is the reconnect grace window (default 120): how long a match survives a dropped human before the opponent wins by abandonment.

Under **MAME on macOS** the Uthernet II is bridged to the host through Apple's vmnet (see `tools/mame/`). `tools/mame/run-mame.sh` boots the disk with `-sl1 uthernet2` and the claudebridge Lua bridge; the host bridge comes up at `192.168.2.1/24` and the guest DHCPs an address from macOS's bootpd, so a server bound to `0.0.0.0:1984` is reachable at the gateway. Start the server, launch MAME, and press N. (KEGS has no Uthernet emulation, so pressing N there takes the no-card path.)

To exercise the server and rules without an IIGS at all:

```bash
python3 server/soak.py --games 20 --red chooser --black greedy  # bot vs bot
python3 server/test_slice.py        # connect -> match -> one human move -> bot reply
python3 server/test_reconnect.py    # token reconnect, bad token, grace/abandonment
python3 server/test_chooser.py      # the search bot beats the greedy bot head-to-head
python3 tools/gen_fixtures.py --check   # golden frames still match protocol.py
```

## Layout

| Path | Contents |
|---|---|
| `src/cc.s` | `CC.SYSTEM` launcher: relocates to $1000, chains TITLE and GAME |
| `src/title.s` | Title screen and options page; `src/title_art.s` is the generated plaque bitmap |
| `src/game.s` | Game part: rules engine and board display go here |
| `src/test.s` | Rules self-tests part (spec section 33); built only when `INCLUDE_TESTS = 1` in `src/shared.s` |
| `src/tables.s` | Rules data: unit class, fuel cost and hit probability tables with their lookups |
| `src/board.s` | Board geometry, directions, 220-cell terrain board and occupant map, terrain flag tables, destruction |
| `src/line.s` | Line classification and tracing shared by movement paths and line of sight |
| `src/units.s` | Unit list as parallel arrays, placement with army limits, occupant upkeep, per-turn fired-at masks |
| `src/events.s` | Event queue from the rules engine to the display layer |
| `src/move.s` | Movement action: validate and price a move, execute it with fuel, terrain HP and event |
| `src/fire.s` | Fire action: validate a shot with its odds, execute with ammo, roll, damage, destruction and events |
| `src/turn.s` | Turns, Shoot Option phases, chess clocks on the tick counter, pause, victory, time loss, surrender, stalemate |
| `src/dbg.s` | Debug board: the original's yellow cursor states, highlights, its two status lines plus a debug message line, the game loop |
| `src/aiplayer.s` | Computer player: a greedy one-ply AI over the engine, for the sides the COMPUTER option assigns |
| `src/net.s`, `src/netdhcp.s` | Uthernet II (W5100) TCP driver and DHCP client for network play |
| `src/proto.s` | Binary protocol: frame encoder and streaming parser, validated against `server/fixtures/` |
| `src/netgame.s`, `src/netplay.s`, `src/netloop.s` | Network client: frame builders, snapshot decode/apply into the engine, and the GAME-loop glue |
| `src/art.s` | Board renderer: every square as the original's 16 x 16 glyph in the board's colours, a unit replacing its square |
| `src/board_art.s` | Generated by `tools/gen_board_art.py`: the board character set, each board's captured look and colours |
| `src/status.s` | Army status display (the original's SELECT screen): the STATUS plaque and the nine-row roster, TAB from the debug board |
| `src/status_art.s` | Generated by `tools/gen_plaque.py` from the captured status screen: the STATUS plaque bitmap |
| `tools/kegs_key.py` | Pokes keys into the running debug board through the KEGS debug socket, with optional screenshot |
| `src/rng.s` | Seedable xorshift32 generator, 0-99 roll, `resolve_hit` with injectable roll |
| `tools/rng_ref.py` | Byte-exact Python mirror of `rng.s` for replay tools and test known answers |
| `src/shared.s` | Equates shared by every part (launcher entries, page $11 globals) |
| `src/common.s` | Routines shared by every part (toolbox start-up, SHR init, text, keys) |
| `res/` | `PRODOS` system file |
| `server/` | Python match server: authoritative `state.py`/`rules.py`, `protocol.py`, `soak.py`, tests, and the golden `fixtures/` |
| `bots/` | Random, greedy, and chooser (search) network bots — ordinary TCP clients of the match server |
| `tools/` | Build and KEGS debugging tools |
| `tools/mame/` | MAME + Uthernet II network harness: `run-mame.sh`, the claudebridge Lua bridge, and `mame-lua` |
| `assets/` | SHR art and audio (empty until milestone 4) |
| `reference/` | Atari capture archive, laid out per the visual checklist |
| `out/` | Build output (generated) |
