#!/usr/bin/env bash
set -euo pipefail
# SDL is a developer dependency; ordinary native Mac builds do not need it.
if ! command -v pkg-config >/dev/null 2>&1; then
  echo 'Install pkg-config and SDL3 (for example: brew install pkgconf sdl3).' >&2
  exit 1
fi
if ! pkg-config --atleast-version=3.4.16 sdl3; then
  echo 'SDL3 >= 3.4.16 is required. On macOS: brew install sdl3.' >&2
  exit 1
fi
printf 'SDL3 %s available.\n' "$(pkg-config --modversion sdl3)"
printf 'Include flags: %s\n' "$(pkg-config --cflags sdl3)"
printf 'Link flags: %s\n' "$(pkg-config --libs sdl3)"
