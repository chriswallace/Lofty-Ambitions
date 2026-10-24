# Tokyo artwork

The game loads `Runtime/atlas.json` and `Runtime/Sheets` through the `TowerArt` Swift package resource bundle. `HD` preserves the earlier generated source pack and the generation prompts.

The fire response uses finished transparent pixel artwork in `Runtime/Sheets/Structure/fire-engine.png`, registered as `vehicle.fireEngine`. The atlas selects its opaque bounds without altering the generated source. The engine preserves its aspect ratio, faces the building, and sits on the same street baseline in both response directions. Firefighters, ladder deployment, and water remain independent animated elements. Created with the built-in image generation tool on 2026-10-24; prompt notes are in `Marketing/Steam/source/key-art-prompts.txt`.

## Windows and city tiles

Rooms with back-wall windows use transparent panes in all six states; windowless rooms remain opaque. Frames, mullions, furniture, lamps and broken glass remain in the foreground artwork. Bathroom mirrors and shower doors remain opaque.

The city is assembled from 24 individually cropped building designs: 12 common, six uncommon, four rare, and two landmarks. Each new game receives a random `scenerySeed`, saved in `TowerState`. Explicit integer hashing chooses weighted designs and irregular spacing as the street grows outward from a fixed origin. Prefix positions are cached per seed so differently sized buildings remain contiguous and panning does not reshuffle them. Immediate duplicates are excluded, and buildings are never mirrored. Placement does not depend on the viewport, simulation clock, or visit order. Older saves receive a repeatable seed during validation and write it on their next save.

`CityBuildings.swift` records each design's floor count and rarity. Per-design weights are 60 / 36 / 12 / 5 for common / uncommon / rare / landmark. With the current catalog, nominal totals are about 72% / 22% / 5% / 1%; excluding the previous facade slightly changes individual draws. Rare styles include the civic clock tower, Art Deco office, conservatory, and garden terraces. The pagoda and observation tower are landmarks. Rarity controls appearance frequency without requiring every kind to appear in every neighborhood.

Buildings use the same camera as the tower. Their floor spacing is about 18 world units compared with the tower's 24, and all entrances align to street level. A 24% sky-colored atmospheric tint applies only to facade silhouettes, separating them from the sharper foreground tower. Panning and zooming reveal more stable buildings, including at negative coordinates.

Each building has registered sunrise, day, sunset and night frames. `CityLighting.swift` blends the buildings and sky with simulation time: dawn from 05:00 to 08:00, dusk from 16:00 to 20:00. `CloudTexture.swift` generates unique cloud silhouettes from seeded density and coherent noise, with pale highlights and soft edges. `CityLayout.swift` varies their proportions, spacing, altitude, opacity and wind speed. Textures are generated on first visibility and held in a bounded cache rather than regenerated every frame. Clouds drift in ambient time, including while paused; Reduce Motion disables drift. Cloud arrangements and shapes share the game's city seed and remain stable when panning.

Windows reveal exactly the same city coordinates as the exterior. A faint blue-white glass tint and stepped white pixel reflections sit behind the room foreground, which masks the effect off walls, furniture and frames. Destroyed and rebuilding rooms omit this intact-glass layer.

Building and room images were generated and edited with the built-in image-generation tool. Prompts are in `HD/Prompts/buildings-*.txt`, `neighborhood-*.txt`, `landmarks-*.txt`, and `windows-*.txt`. Building source sheets are 1536 × 1024. Atlas rectangles crop individual assets at runtime without altering source PNGs. Nearest-neighbor sampling preserves pixel detail. The earlier four-cloud sheet and `cloud-varieties.txt` prompt remain as source references; the live sky now uses procedural textures. Earlier panorama and repeating-block experiments remain in `HD/CityPanorama` and `HD/CityBlocks` and are not bundled.

## Room placement rule

Every room can sit between other rooms. Left and right side walls must be solid, opaque shared walls in all six states, including destroyed and rebuilding. Windows belong only on the flat back wall, with transparent panes for the dynamic city view. Never assume a room occupies an exterior end of the tower. Keep doors and wall perspective consistent across states.

## Interior variations and furniture poses

Generated with the built-in image-generation tool using the existing office, apartment, and civilian sheets as style references. No external artwork was supplied. The six outputs are copied unchanged into the runtime bundle; source cropping is recorded in `Runtime/atlas.json`.

- `Runtime/Sheets/Rooms/office2.png` — sage design studio, six states (1774 × 887).
- `Runtime/Sheets/Rooms/office3.png` — brick creative loft, six states (1774 × 887).
- `Runtime/Sheets/Rooms/apartment2.png` — warm Japanese studio, six states (1182 × 1330).
- `Runtime/Sheets/Rooms/apartment3.png` — blush-and-teal studio, six states (1182 × 1330).
- `Runtime/Sheets/Rooms/luxuryApartment.png` — walnut-and-brass residence, six states (2048 × 768).
- `Runtime/Sheets/Characters/room-poses.png` — four people × typing, reading, and reclining, transparent alpha (1254 × 1254).

Final prompts are in [HD/Prompts/room-variations](HD/Prompts/room-variations). The existing office and apartment art remain style 1. New rooms use solid walls without exterior windows. `RoomActivity.swift` records furniture anchors and staggered ambient activities. `TowerAtlas.roomPoint` maps anchors through the same stretching as the room artwork; character anatomical scale remains independent of the room’s width. No occupants are baked into room sheets. Nighttime apartment lighting uses the closed-lighting frame while independent residents remain visible.

Civilian frames have a `footAnchor` in source pixels, measured from the lower-left of each crop. Its X coordinate registers the head/body axis (the opaque upper 32% of the figure); Y removes transparent pixels below the soles. Mirroring keeps that anchor in place. Each character's standing opaque height supplies one `referenceHeight` for the entire pose row, so padded seated frames cannot shrink their walking figure. Source PNGs remain unchanged.

Upright room occupants use the visible floor lane measured for each interior, with short distance-based strolls and standing pauses before walking and turning. Personal lanes avoid neighboring furniture occupants; residents remain in bed at night. `ActorMotion` interpolates traveler display positions between simulation updates, preserves stationary heading, and shares a distance-based walking cycle with room occupants. Frames 1 and 2 alternate planted feet, with closed-leg frame 0 between them. Elevator queues show a spaced, grounded sample of up to eight passengers, while the simulation retains every passenger. Presentation state is transient and resets when another tower loads.
