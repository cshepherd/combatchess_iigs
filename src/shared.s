*----------------------------------------------------------
* shared.s - equates shared by every part (PUT at the top
* of each part). No code or data here: this file is
* included into more than one binary.
*----------------------------------------------------------

* Build flag: include the rules self-tests (TEST part, the T
* option on the title). 0 = leave them out (default); 1 = build
* and wire them in. The Makefile reads this same line to decide
* whether to assemble TEST and add it to the disk image, so this
* is the single switch -- flip it to 1 to bring the tests back.
INCLUDE_TESTS = 0

* Launcher jump table (src/cc.s). JMP here in emulation
* mode with 8-bit M/X to chain to another part.
LAUNCH_TITLE = $1000
LAUNCH_GAME  = $1002
LAUNCH_TEST  = $1004

* Cross-part globals in page $11. The launcher zeroes this
* page once at boot; values written here survive chaining
* between TITLE and GAME.
tb_inited = $1100        ; byte: nonzero once toolbox_init has run
myID      = $1102        ; word: Memory Manager user ID

* Game options (spec 29), set on the title screen's options
* page and read by GAME. Ranges and defaults are the Atari
* original's, captured in reference/notes/options_ranges.md.
cfg_board       = $1104  ; 1-10
cfg_tanks_black = $1105  ; 0-3
cfg_tanks_red   = $1106  ; 0-3
cfg_cars_black  = $1107  ; 0-5
cfg_cars_red    = $1108  ; 0-5
cfg_first       = $1109  ; SIDE_RED (0) or SIDE_BLACK (1) starts
cfg_computer    = $110A  ; CFG_CPU_*: who the computer plays
cfg_time_black  = $110B  ; minutes, 1-30
cfg_time_red    = $110C  ; minutes, 1-30
cfg_moves       = $110D  ; moves per turn, 1-20
cfg_shoot       = $110E  ; Shoot Option 1 or 2
cfg_valid       = $110F  ; CFG_MAGIC once cfg_defaults has run
CFG_MAGIC       = $A5
CFG_CPU_BLACK   = 0      ; in the original's SELECT order
CFG_CPU_RED     = 1
CFG_CPU_NONE    = 2
CFG_CPU_BOTH    = 3

* A key for the next frame, poked by tools/kegs_key.py.
* wait_key and the debug board loop both honour it.
inject_key      = $1110  ; word

* Which bot a QUEUE_BOT network game asks for (options screen). Outside the
* cfg_valid block ($1104-$110F is full); cfg_defaults still initialises it.
cfg_bot_level   = $1112  ; byte: 0 random, 1 greedy, 2 chooser (CFG_BOT_*)
CFG_BOT_RANDOM  = 0
CFG_BOT_GREEDY  = 1
CFG_BOT_CHOOSER = 2
CFG_BOT_MAX     = 2

* Sound samples (SOUNDS file) are loaded once into a Memory-Manager
* bank; the base persists here across the title/game cycle so GAME
* re-patches its parameter blocks each run without reloading.
snd_blk         = $1120  ; long: base address of the loaded sample bank
snd_loaded      = $1124  ; byte: nonzero once cc.s load_res has run (once/boot)

* The status-screen plaque (12.8 KB) lives in its own bank, not the GAME
* image, so GAME stays under $BEFF. cc.s loads the SA resource here at boot
* (like SOUNDS/NT/TM) and status.s block-moves it to the screen from here.
STATUS_ART_BANK = $05    ; spare fast-RAM bank holding the status plaque bitmap

* Network play (spec N4). Nonzero selects a network game: GAME
* connects to the match server instead of running a local hot-seat.
net_mode        = $1130  ; byte: 0 local, nonzero network game
net_human       = $1131  ; byte: in a net game, 1 waits for a human, 0 plays a bot

* Heartbeat task record (see toolbox_init): 20 bytes the
* firmware keeps a pointer to for the whole session, so it
* sits outside every part, above the globals page.
HB_TASK = $1200

* Sound Tool Set work area: one direct page, in the free
* bank-0 span between the heartbeat record and QuickDraw's
* direct page. Passed to _SoundStartUp by toolbox_init.
SOUND_DP = $1C00

* QuickDraw II direct page: 3 pages, fixed just below the
* parts' load address. Allocated from the Memory Manager by
* toolbox_init so the record matches what we use.
QD_DP = $1D00

* Toolbox dispatcher.
TOOLBOX = $E10000

* Rules-engine scratch in the direct page (D = $0000). Only
* live inside one routine, never across a toolbox or MLI
* call. ProDOS 8 and the toolbox leave this range alone;
* ddiigs uses the same one.
rt0   = $E0
rt1   = $E1
rt2   = $E2
rt3   = $E3
rptr  = $E4              ; 2-byte pointer
rptr2 = $E6              ; 2-byte pointer
rt4   = $E8
rt5   = $E9
rt6   = $EA
rt7   = $EB
