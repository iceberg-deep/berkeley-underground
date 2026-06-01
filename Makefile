# Berkeley Underground — Box 1 build pipeline
#
# Stages (each is an idempotent, re-runnable script under build/):
#   deps    install/verify host tools (qemu, genisoimage, pexpect)
#   fetch   download + checksum FreeBSD install media and distribution sets
#   iso     build the install CD-ROM image from the distribution tree
#   install create the qcow2 and drive a scripted install under QEMU (SLOW: TCG)
#   inject  plant the real weaknesses + breadcrumbs + loot tarball (offline)
#   theme   apply the disclosed cosmetic SunOS costume
#   build   = deps fetch iso install inject theme   (the whole pipeline)
#
# 'inject' and 'theme' are delivered together via a guest firstboot hook
# (tar-on-raw-disk channel) because this dev host cannot mount UFS — see
# docs/field-manual.md "Why injection runs inside the guest".

SHELL := /bin/sh
B := build

.PHONY: build dist-image deps fetch iso install inject theme luks solve run clean distclean verify help

help:
	@echo "Targets: deps fetch iso install inject theme luks  | build | dist-image | run | solve | verify | clean | distclean"

deps:    ; $(B)/00-deps.sh
fetch:   ; $(B)/10-fetch-media.sh
iso:     ; $(B)/20-make-iso.sh
install: ; $(B)/30-install.sh
inject:  ; $(B)/40-inject.sh
theme:   ; $(B)/50-theme.sh
luks:    ; $(B)/70-luks.sh
solve:   ; $(B)/95-solve.sh

# Full pipeline, in order.  (luks is a separate packaging step — see 'dist'.)
build: deps fetch iso install inject theme
	@echo "=== build complete: dist/ ==="

# Distributable: the full build, then wrap the disk in LUKS for shipping.
dist-image: build luks
	@echo "=== encrypted distributable ready: dist/ ==="

# Boot the finished box (host-only). See run.sh.
run:
	./run.sh

# Sanity-check the emitted artifacts without launching the full solve.
verify:
	$(B)/90-verify.sh

# Remove build scratch but keep downloaded media + the finished image.
clean:
	rm -rf work

# Remove everything reproducible (media + images + scratch).
distclean: clean
	rm -rf media dist
