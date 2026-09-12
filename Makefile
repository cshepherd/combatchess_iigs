# Combat Chess — Apple IIGS port.
#
#   make package   assemble every part and build out/combatchess.po
#   make clean     remove out/ and merlin32 listings
#
# The volume boots straight into CC.SYSTEM (src/cc.s), a tiny
# launcher that relocates to $1000 and chains TITLE -> GAME -> TITLE.
# Same toolchain and layout as ../ddiigs: merlin32 for 65816
# assembly, cadius (through a strict wrapper) for the ProDOS image,
# tools/packbytes.py for PackBytes-compressed SHR art once we have it.

VOLNAME = combatchess
IMGFILE = out/$(VOLNAME).po

# Cadius wrapper that exits non-zero on "Error : ..." output. Plain
# cadius reports e.g. "No enough space in the image" and exits 0,
# letting make silently produce a disk image with missing files.
CADIUS = tools/cadius_strict.sh

# Parts: each src/NAME.s assembles to out/NAME. ProDOS filenames
# and file types are assigned in the package step. The rules
# self-tests (TEST) are built and added only when src/shared.s sets
# INCLUDE_TESTS = 1 -- the same switch the source conditionals read.
INCLUDE_TESTS := $(shell grep -E '^INCLUDE_TESTS *=' src/shared.s | grep -oE '[01]' | tail -1)
PARTS = cc title game
ifeq ($(INCLUDE_TESTS),1)
PARTS += test
endif
BINS  = $(addprefix out/,$(PARTS))

# Sources included with PUT by more than one part. Listed as
# prerequisites so editing them rebuilds every part.
SHARED = src/shared.s src/common.s src/tables.s src/board.s src/line.s src/units.s src/events.s src/move.s src/rng.s src/fire.s src/turn.s src/aiplayer.s src/dbg.s src/boards.s src/net.s src/netdhcp.s src/proto.s src/netgame.s src/netplay.s src/netloop.s

# The ten boards, generated from the reference maps captured from the
# Atari original (tools/atari_boards_decode.py writes them).
src/boards.s: tools/gen_boards.py $(wildcard reference/maps/board*.txt)
	python3 tools/gen_boards.py

# The title plaque bitmap, generated from the captured title screen.
src/title_art.s: tools/gen_title_art.py reference/raw/title/title_plaque.bin reference/raw/title/title_charset.bin reference/raw/title/title_info.json reference/raw/title/title.png
	python3 tools/gen_title_art.py

out/title: src/title_art.s

# The STATUS plaque bitmap, generated from the captured status screen.
src/status_art.s: tools/gen_plaque.py reference/raw/status/status_own_mode7_7D2C.bin reference/raw/status/status_charset.bin
	python3 tools/gen_plaque.py --codes reference/raw/status/status_own_mode7_7D2C.bin --rows 5 --charset reference/raw/status/status_charset.bin --slots 8,14,0,11,9 --label status --out src/status_art.s

# The board character set, looks and colours from the captured boards.
src/board_art.s: tools/gen_board_art.py reference/raw/boards/board_charset.bin reference/raw/boards/boards_capture.json $(wildcard reference/raw/boards/board*_codes.txt) $(wildcard reference/raw/boards/board*.png)
	python3 tools/gen_board_art.py

out/game: src/status.s src/art.s src/board_art.s src/sound.s src/sound_samples.s
# The status plaque is no longer linked into GAME; it builds on its own and
# ships as the SA resource, loaded into STATUS_ART_BANK at boot (see cc.s).
out/status_art: src/status_art.s

.PHONY: all package clean
all: package
package: $(IMGFILE)

# merlin32 writes NAME (no extension) beside the source and, with
# -V, a NAME_Output.txt listing that tools/kegs_screenshot.py uses
# to resolve symbols for KEGS debugging.
out/%: src/%.s $(SHARED)
	mkdir -p out
	cd src && merlin32 -V $*.s
	mv src/$* out/$*

$(IMGFILE): res/PRODOS res/sounds.bin res/ntpplayer res/title.ntp res/ccc.shr $(BINS) out/status_art
	mkdir -p out
	rm -f $(IMGFILE)
	$(CADIUS) CREATEVOLUME $(IMGFILE) $(VOLNAME) 800KB --quiet
	cp res/PRODOS out/PRODOS\#FF0000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/PRODOS\#FF0000 --quiet
	rm out/PRODOS\#FF0000
	# Launcher. It is the only .SYSTEM file on the volume, so ProDOS
	# runs it at boot. SYS files always load at $$2000 (#FF2000).
	cp out/cc out/CC.SYSTEM\#FF2000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/CC.SYSTEM\#FF2000 --quiet
	rm out/CC.SYSTEM\#FF2000
	# TITLE, GAME (and TEST) are chained by the launcher, never booted
	# on their own, so they are BIN ($$06) not SYS -- CC.SYSTEM is the
	# only launchable system file. They still load at $$2000 (#062000).
	cp out/title out/TITLE\#062000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/TITLE\#062000 --quiet
	rm out/TITLE\#062000
	cp out/game out/GAME\#062000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/GAME\#062000 --quiet
	rm out/GAME\#062000
	# Ripped sound-effect samples, loaded into a spare bank at game start.
	cp res/sounds.bin out/SOUNDS\#060000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/SOUNDS\#060000 --quiet
	rm out/SOUNDS\#060000
	# NinjaTracker+ player (bank $$03) and the title-music module (bank
	# $$04), loaded by cc.s at boot; TITLE plays the module on its screen.
	cp res/ntpplayer out/NT\#060000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/NT\#060000 --quiet
	rm out/NT\#060000
	cp res/title.ntp out/TM\#060000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/TM\#060000 --quiet
	rm out/TM\#060000
	# The status-screen plaque (12.8 KB), loaded into its own bank at boot so
	# it does not eat into GAME's $$2000-$$BEFF window.
	cp out/status_art out/SA\#060000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/SA\#060000 --quiet
	rm out/SA\#060000
	# The cCc brick-wall boot logo (32 KB raw SHR), loaded into its own bank
	# at boot; TITLE fades it in and out once before the title, on a cold boot.
	cp res/ccc.shr out/CCC\#060000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/CCC\#060000 --quiet
	rm out/CCC\#060000
ifeq ($(INCLUDE_TESTS),1)
	# Rules self-tests: T on the title screen, or 00/1004g in KEGS.
	cp out/test out/TEST\#062000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/TEST\#062000 --quiet
	rm out/TEST\#062000
endif
	$(CADIUS) CATALOG $(IMGFILE)

clean:
	rm -rf out src/*_Output.txt src/_FileInformation.txt
