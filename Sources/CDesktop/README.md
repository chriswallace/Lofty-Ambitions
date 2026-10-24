# Portable desktop bridge

`include/CDesktop.h` is the entire plain-C boundary. SDL types stay private.
All API calls are made on the main thread. Build with C11 and SDL3 >= 3.4.16.
The Windows release dependency is pinned to official SDL 3.4.16. The original Mac
development build used Homebrew SDL 3.4.0; revalidation with 3.4.16 is pending.

## Build and dependency setup

On macOS install SDL3/pkg-config, run `scripts/bootstrap-desktop.sh`, and pass
`pkg-config --cflags sdl3` / `pkg-config --libs sdl3` to the compiler/linker.
A universal Mac package needs a matching SDL library for each architecture;
Homebrew's local ARM library alone does not provide Intel support.

On Windows run `scripts/bootstrap-desktop.ps1` in the same PowerShell session as
the build. The script verifies the official VC development ZIP's SHA-256 and
sets `SDL3_ROOT`, `SDL3_INCLUDE`, `SDL3_LIB`, and `PATH`. Compile with
`-I <SDL3_INCLUDE>` and link with `-L <SDL3_LIB> -lSDL3`. Ship the x64 `SDL3.dll`
beside the executable, SDL's `LICENSE.txt`, and `Vendor/stb/LICENSE`. Swift runtime
packaging is handled by the application build script. Windows execution is not
verified by a Mac build of this bridge.

SDL source/release: https://github.com/libsdl-org/SDL/releases/tag/release-3.4.16

Archive: `SDL3-devel-3.4.16-VC.zip`

SHA-256: `1a784cb2a5c64d56fe7a62090fe9d242d9865f235e4ea9678f1a6ba4e693e7de`

Digest checked against the official GitHub release API and independently against
the downloaded archive. A verbatim SDL license is included as `SDL-LICENSE.txt`.
Pinned stb source, hashes and license are in `Vendor/stb/README.md`.

## Rendering and input contracts

Coordinates are logical window units. The renderer is scaled to the window's
physical pixel output each frame; SDL mouse coordinates already use window units.
Resize events report logical width/height in x/y. Wheel deltas use SDL scroll
units, positive Y upward, with SDL's flipped-direction flag normalized. Button
values are SDL's numeric convention: 1 left, 2 middle, 3 right. Key events include
repeats; use text-input events for Unicode typing rather than key codes.

Colors are straight `0xRRGGBBAA`. PNGs use nearest-neighbor filtering. `lt_pixels`
accepts premultiplied RGBA8 and converts to straight alpha before upload. Dynamic
keys identify immutable pixels and must change if content changes. Dynamic images
use a separate 512-entry / 64-MiB LRU cache; file textures retain their own
96-entry / 256-MiB cache so a wide sky cannot evict sprite sheets. Cached dynamic
textures can be drawn without regenerating their pixels. The desktop frontend
generates at most two missing clouds per frame to keep resize/zoom responsive.
Text uses a separate
256-entry / 32-MiB LRU cache, keyed by content, pixel font size, weight and color.
Physical font rasterization follows display density.
The frontend chooses a UI scale from display content scale and native window
size. `lt_window_size` returns native coordinates; `lt_size` returns the scaled
layout viewport. `lt_set_ui_scale` applies equally to rendering, font density,
mouse positions, and drag distances; wheel steps remain unchanged. The default
UI is at least 125% when space permits and becomes 200% in a maximized 4K window.
The toolbar size preference is stored separately from tower saves.

Text input is limited to
4096 UTF-8 bytes per drawing call. Oversized textures are rejected. Capture must
occur after drawing and before `lt_present`; it writes physical-resolution PNGs.

Fonts are loaded from installed Segoe UI/Arial on Windows and Arial on macOS.
For development, `LOFTY_FONT` and `LOFTY_FONT_BOLD` may point to installed TTFs.
No system font is redistributed. The UTF-8 decoder validates scalar values and
stb_truetype handles kerning and glyph rasterization. Unsupported glyphs use the
font's question-mark glyph. Complex-script shaping and cross-font fallback are
not implemented.

File-dialog callbacks can arrive on a background thread. They only copy results
into a mutex-protected queue; `lt_poll` produces the result on the main thread.
Queue references protect against a dialog completing after window destruction.
An empty result represents cancellation or an OS dialog failure. The returned
UTF-8 string is valid until the next `lt_poll` or `lt_destroy`. Only one dialog
should be requested at a time by the application. The bridge never opens or
writes game saves; `lt_capture` writes only the explicitly supplied screenshot.
