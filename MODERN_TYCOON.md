# Modern Tycoon

Modern Tycoon is an independent OpenTTD modernization program: a compatible fork for deeper simulation and native systems, plus first-party GameScript, NewGRF/NML, and OpenGFX2-derived content packs.

The project starts with a playable market laboratory and grows toward company and industry finance, a structured newspaper, richer economic cycles and contracts, modern vehicles, fictional future transport, high-resolution art, contemporary UX, and measured performance work.

The current branch includes both the playable GameScript laboratory and an intentionally unreachable native C++ type/arithmetic/conservation spine. The latter is the tested base for synchronized commands and save chunks; it is not yet a native in-game exchange.

Start here:

- [Masterplan](docs/modern_tycoon/MASTERPLAN.md)
- [Architecture and compatibility contract](docs/modern_tycoon/ARCHITECTURE.md)
- [Native Company Exchange implementation map](docs/modern_tycoon/NATIVE_MVP_FILEMAP.md)
- [Development and verification](docs/modern_tycoon/DEVELOPMENT.md)
- [Current status](docs/modern_tycoon/STATUS.md)
- [Verified baseline report](docs/modern_tycoon/VERIFICATION_2026-07-16.md)
- [Vehicle and art contract](docs/modern_tycoon/VEHICLES_AND_ART.md)
- [Curated content playtest](docs/modern_tycoon/CURATED_CONTENT.md)
- [Playable GameScript prototype](extensions/modern_tycoon_gs/README.md)

This work intentionally remains separate from the official OpenTTD contribution path. Official OpenTTD prioritizes a stable, classic-compatible core and explicitly does not accept AI-generated code. Modern Tycoon is therefore maintained as its own GPL-2.0 fork; no generated change from this repository should be submitted upstream.

SPDX-License-Identifier: GPL-2.0-only
