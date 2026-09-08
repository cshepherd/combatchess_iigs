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
# and file types are assigned in the package step.
PARTS = cc title game test
BINS  = $(addprefix out/,$(PARTS))

# Sources included with PUT by more than one part. Listed as
# prerequisites so editing them rebuilds every part.
SHARED = src/shared.s src/common.s src/tables.s src/board.s src/line.s src/units.s src/rng.s

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

$(IMGFILE): res/PRODOS $(BINS)
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
	cp out/title out/TITLE\#FF2000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/TITLE\#FF2000 --quiet
	rm out/TITLE\#FF2000
	cp out/game out/GAME\#FF2000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/GAME\#FF2000 --quiet
	rm out/GAME\#FF2000
	# Rules self-tests: T on the title screen, or 00/1004g in KEGS.
	cp out/test out/TEST\#FF2000
	$(CADIUS) ADDFILE $(IMGFILE) /$(VOLNAME)/ out/TEST\#FF2000 --quiet
	rm out/TEST\#FF2000
	$(CADIUS) CATALOG $(IMGFILE)

clean:
	rm -rf out src/*_Output.txt src/_FileInformation.txt
