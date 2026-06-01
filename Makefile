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

.PHONY: build dist-image deps fetch iso install inject theme luks solve package shiptest run clean distclean verify help \
        box2 box2-luks box2-package box2-solve box2-shiptest box2-dist

help:
	@echo "Targets: deps fetch iso install inject theme luks package | build | dist-image | run | solve | verify | clean | distclean"

deps:    ; $(B)/00-deps.sh
fetch:   ; $(B)/10-fetch-media.sh
iso:     ; $(B)/20-make-iso.sh
install: ; $(B)/30-install.sh
inject:  ; $(B)/40-inject.sh
theme:   ; $(B)/50-theme.sh
luks:    ; $(B)/70-luks.sh
solve:   ; $(B)/95-solve.sh
package: ; $(B)/99-package.sh
shiptest:; $(B)/98-shiptest.sh

# ── Box 2 "The Traced Call" — clones the Box 1 base; reuses the pipeline ────────
box2:          ; $(B)/40-inject2.sh
box2-luks:     ; BOX_ENV_FILE=box2.env $(B)/70-luks.sh
box2-package:  ; BOX_ENV_FILE=box2.env BOX_README=mk-player-readme2.sh $(B)/99-package.sh
box2-solve:    ; $(B)/95-solve2.sh
box2-shiptest: ; BOX_ENV_FILE=box2.env BOX_SOLVE_DRIVER=drive_solve2.py $(B)/98-shiptest.sh
box2-dist: box2 box2-luks box2-package
	@echo "=== Box 2 release bundle ready: dist/release/box2-teal/ ==="

# Full pipeline, in order.  (luks is a separate packaging step — see 'dist'.)
build: deps fetch iso install inject theme
	@echo "=== build complete: dist/ ==="

# Distributable: full build → LUKS-wrap → player release bundle.
dist-image: build luks package
	@echo "=== release bundle ready: dist/release/ + dist/*-release.tar.gz ==="

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
