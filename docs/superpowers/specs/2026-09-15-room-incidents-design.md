# Room incidents

Approved in conversation: hotel parties and cleanup, apartment arrears and court eviction, fires with visible FD ladder and water response, and persistent emotional speech bubbles for every issue.

## Simulation

Native Swift/AppKit, macOS 13+, no external dependencies. Add an optional Codable incident to each room so old saves still load. A single incident occupies a room until resolved; fire and hotel cleanup stop earnings, arrears retain tenants without rent. Explicit response actions advance timed stages. The shared room signal describes incidents, existing warnings, low happiness, and brief relief after resolution. Save and validate every stage, timer, cost, and responder assignment.

Hotel parties last 120 game minutes and annoy same-floor neighbors, then await housekeeping. A connected team within five floors can clean one room at a time; cleanup takes 180 minutes. Apartment notices take one day, court proceedings two days after a $500 filing, and court-authorized eviction takes 120 minutes. These are fictional game mechanics. Arrears are written off at eviction. Fires worsen until responders arrive; FD dispatch books $1,500 to expenses and remains available even with low cash. Ladders reach floor 7; taller rooms use an interior stair response with a longer arrival. Extinguishing takes 180 minutes; repairs require payment and 240 minutes. Active incidents prevent demolition. Occasional deterministic events begin on day 3, at most one new event per day and three active at once. Controlled triggers live in an explicit incident sandbox menu.

## Presentation

Persistent compact face bubbles in every affected room; priority incidents override ordinary warnings. Use expressions and pictograms as well as colors. Selected or hovered bubbles expand to text; clicking opens the room inspector. A native incident list provides access when zoomed out or off screen. Inspector shows status, remaining game time, arrears, and applicable response actions. Render room trash, flames/smoke, truck arrival, extending ladder, firefighters, and water spray. Pause freezes animation; reduced motion uses static representative visuals.

## Verification

Test workflows, invalid actions, staffing capacity/access, income and occupancy effects, deterministic generation, save round trips, legacy saves, and corrupt incident rejection. Build both supported architectures and visually inspect a paused incident demonstration without touching autosaves.
