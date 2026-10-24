# Lofty Ambitions — Steam promo kit

A whole city. One tower.

## Finished assets

- `video/Lofty-Ambitions-Gameplay-Trailer-1080p.mp4`: 32-second gameplay trailer with animated headlines, real room activity, construction time-lapse, elevator traffic, underground venues, fire response, an illustrated finale, and an original upbeat synth soundtrack.
- `video/Lofty-Ambitions-Teaser-1080p.mp4`: 12-second cut featuring construction, emergencies, and the title reveal.
- `video/Lofty-Ambitions-Concept-Reveal-1080p.mp4`: 8-second illustrated cover-art motion piece with a slow push-in and pixel sparkles. This is concept art, not gameplay.
- `capsules/`: main 1232×706, header 920×430, vertical 748×896, small 462×174. Only the game title appears in the cover artwork.
- `screenshots/`: eight 1920×1080 gameplay images, including the native building interface. These have no promotional text added.
- `loops/`: three repeating GIFs for construction, room activity, and emergency response. Each loop runs forward then backward for a smooth repeat, about six seconds total.
- `preview/`: review stills and an overview sheet. These are for reviewing the kit, not the Steam screenshot slot.

## What the footage shows

Captured from the production Swift simulation and pixel renderer in deliberately staged demonstration towers. Construction and simulation time are accelerated. The same room catalogue, occupants, elevators, incidents, and fire response are available in the game. Focus-mode views omit the native controls; screenshot 08 includes them. No player saves were loaded or changed.

The fire engine is finished transparent pixel artwork, integrated into the game's runtime atlas as `vehicle.fireEngine`. It replaces the earlier rectangle-based engine in the game itself. Its direction and aspect ratio are preserved, with independent firefighters, ladder movement, and water effects. The rebuilt local app includes it too.

The cover art and trailer finale are AI-generated illustrations derived from the existing official Lofty Ambitions branding. Use those in capsule/concept placements; use the screenshots folder for gameplay screenshots. The edit avoids release dates, review scores, platform compatibility claims, and availability claims because those have not been supplied.

## Video and sound

All three videos: 1920×1080, 30 fps, H.264 video, AAC stereo audio, MP4 with fast-start metadata. Trailer targets 12 Mbps; shorter edits target 10 Mbps. The soundtrack, “Skyline Spark,” is an original procedural composition at 120 BPM created for this kit, with no sampled third-party music. The WAV master is in `source/skyline-spark-original.wav`. It is promotional music; the game does not currently contain this soundtrack.

## Suggested Steam use

Upload the 32-second trailer first. Use the capsule files in their matching store slots. Lead screenshots with 01, 03, 06, 07, and 08, then add 04 and 05 for more detail. Use the GIFs in the store description or announcements. Nothing has been uploaded or published.

Dimensions and export settings were checked against [Steamworks store graphical assets](https://partner.steamgames.com/doc/store/assets/standard) and [Steamworks trailers](https://partner.steamgames.com/doc/store/trailer) on 2026-10-24. Steam processes trailer poster and thumbnail images after upload.

## Rebuilding

From the repository root, `bash Marketing/Steam/source/capture.sh` recreates gameplay sources and screenshots using existing Debug build products. Pass `--scene 6` to regenerate only the emergency scene, or `--stills` for still images. The capture harness never writes saves. Build the game first if the production sources or artwork changed.

Run `python3 Marketing/Steam/source/assemble.py` to rebuild capsules, the soundtrack, edits, and GIFs. Requires local FFmpeg, Pillow, and NumPy. `--refresh-emergency` reuses the existing six unaffected scene edits. Original generated key art and reusable graphic overlays are retained under `source/`.
