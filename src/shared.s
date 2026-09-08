*----------------------------------------------------------
* shared.s - equates shared by every part (PUT at the top
* of each part). No code or data here: this file is
* included into more than one binary.
*----------------------------------------------------------

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
* $1104-$11FF free: game options chosen on the title screen
* (board, army sizes, first mover, time limit, moves per
* turn, shoot option) belong here so GAME can read them.

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
