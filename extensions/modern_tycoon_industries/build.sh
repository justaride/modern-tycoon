#!/usr/bin/env bash
# Rebuild Modern Tycoon Space Industry from source: sprites, NML and the .grf.
#
# Needs Python 3 with the official NML compiler, Pillow and PyYAML:
#   python3 -m venv ~/src/.venv-nml && ~/src/.venv-nml/bin/pip install nml pillow pyyaml
# Set NML_VENV to use another virtual environment.
#
# Usage: ./build.sh [--update-docs]   (--update-docs refreshes the committed preview images)
#
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")"

VENV="${NML_VENV:-$HOME/src/.venv-nml}"
if [[ -x "$VENV/bin/nmlc" ]]; then
	PY="$VENV/bin/python"; NMLC="$VENV/bin/nmlc"
else
	PY="$(command -v python3)"; NMLC="$(command -v nmlc || true)"
	[[ -n "$NMLC" ]] || { echo "nmlc not found; see the header of build.sh" >&2; exit 1; }
fi

rm -rf generated
"$PY" tools/build_pack.py
"$NMLC" -c --lang-dir=lang --grf=generated/modern_tycoon_space.grf generated/modern_tycoon_space.nml
"$NMLC" --version | head -1 > generated/nmlc_version.txt
shasum -a 256 generated/modern_tycoon_space.grf | tee generated/modern_tycoon_space.grf.sha256

if [[ "${1:-}" == "--update-docs" ]]; then
	mkdir -p ../../docs/modern_tycoon/images
	for f in spaceport.gif spaceport.png fuel_plant.png refinery.png; do
		cp "generated/preview_$f" "../../docs/modern_tycoon/images/modern_tycoon_space_$f"
	done
fi
