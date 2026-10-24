# Coverage overlay

User request: see areas needing food or shops while deciding where to build.

Implementation choices: an Off / Food / Shops toolbar selector, persistent across construction-tool changes. Existing cached neighborhood allocation drives colored room tints and percentage labels: teal for fully served, amber for partially served, red for none. Relevant venues use blue with served/capacity labels; vacant and inactive consumer rooms use gray. Hover details explain shortages. Labels are omitted when too small to fit, while room tints and hover details remain available. Exact equivalent service data remains in accessible native room inspectors and Issues.

Matching valid construction previews, including dragged rows, show geometric reach bands on connected built floors. Selecting an existing operational venue also shows its reach. The legacy shaft gap is excluded from construction-cell distances. Capacity is not forecast, and current percentage labels remain unchanged until construction. Invalid or disconnected candidate sites have no reach guide. Empty space carries no demand.

The overlay uses no saved state and does not modify simulation behavior. Focus hides it temporarily and restores the selection on return. Add-nearby actions select the appropriate overlay. Active incident badges remain visible; other ordinary badges give way to coverage labels. The legend shields obscured construction cells from clicks.

Verification: native selector regression observed failing before implementation. Full 194-test core suite passes. Native checks cover mode switching, shortage labels, hover reasons, minimum-size layout, valid/invalid/drag guides, immediate construction recovery, existing-provider reach, focus restoration, vacant/inactive states, low zoom, hit testing, legend shielding, and unchanged encoded game data. Before/after render previews inspected.

Review caught hover detail resizing its own hit region; a native regression reproduced it before reserving a fixed detail area.
