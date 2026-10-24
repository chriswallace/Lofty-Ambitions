# Continue on the PC

Repository: https://github.com/chriswallace/Lofty-Ambitions

Clone this repository on your Windows 11 x64 PC and open its folder in Codex.
The current checked-in game includes the native Mac app and portable Windows
frontend, shared simulation/session/rendering/artwork, Windows packaging, and
cross-platform CI. The last Mac verification passed 223 tests, native UI checks,
portable SDL smoke checks, and byte-identical replay parity. The first local
Windows run now passes 215 tests, replay parity, source/packaged GUI smoke,
and native save/open checks using SDL 3.4.16. Clean-machine packaging and full
manual acceptance remain pending. See verification/windows-2026-10-24.txt.

## First Windows run

Follow [WINDOWS.md](WINDOWS.md) or the root WINDOWS-START-HERE.txt. Install the
pinned Swift 6.4.1 toolchain and its official Windows prerequisites, then run
from PowerShell in the project folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

Keep the generated diagnostics ZIP, including if a stage fails. Do not change
the replay baseline merely to hide a platform mismatch.

## Steam sign-in — pending

The user will set up Steamworks on the PC. A real App ID and official Steamworks
SDK have not yet been supplied. **Steam authentication has not been implemented
or tested in this commit.** Do not claim a development App ID or mock session is
authentication for Lofty Ambitions.

The intended integration uses the existing Steam client's session through an
official SDK bridge shared by both frontends. The game must never request a
Steam password or ship a publisher/API secret. Steam builds should verify their
configured App ID, initialize before accessing interfaces, handle restart and
shutdown, and keep local identity separate from any future backend verification.
Preserve the standalone development build and normal offline gameplay policy.
Keep licensed SDK downloads and steam_appid.txt out of Git and release depots.

## Security audit — incomplete

The Cloudflare security-audit skill completed source reconnaissance, a hunter
wave, and one coverage critic. Independent candidate validation, the final
critic, and dynamic sandboxed checks remain pending. There are no confirmed
findings. The three source proposals and their coverage links are retained in
[the audit handoff](../security/audit-2026-10-24/REPORT.md). Continue that workflow,
verify the proposed boundaries independently, then apply narrow fixes and
regression checks. Respect the skill's isolated execution requirements.

Areas worth checking include imported geometry/totals before arithmetic,
bounded file reads, per-run temporary image paths, async dialog correlation,
and a failed glyph allocation. These are review leads/hardening notes, not
verified exploitation claims.

## Source and media

Git contains runtime artwork needed to build/play, all game source/tests, the
Windows tooling, and marketing source scripts. Large artwork-authoring archives,
generated game binaries, local saves, downloaded SDKs, and finished video/ZIP
exports stay outside Git. Those local files have not been deleted. The finished
Steam promo kit remains on the originating Mac.
