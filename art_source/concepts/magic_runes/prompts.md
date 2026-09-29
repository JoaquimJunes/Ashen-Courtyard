# Dictionary v01 — authoring record

User request: “Yes this meaning-to-shape mapping works, lets start developing the visual rune dictionary”.

Method: deterministic vector layout using existing rune drawing coordinates and two optical crown transcriptions, followed by a local browser PNG export. No image-generation model, generation prompt, internet reference retrieval or interactive preview was used.

Authoring brief: present the twelve approved meaning-to-shape assignments as one static dictionary sheet; show clean normalized glyphs, exact names, concise approved meanings, category labels and each rune's mana-gauge location. Include unchanged views of the original gauge regions for comparison. Use readable typography, charcoal panels and restrained violet glyphs. Preserve the original artwork and HUD code. Clearly distinguish approved meanings from drawings awaiting review.

Reference: [approved mana-gauge close-up](../../ui/soulbound_hud/concepts/evolution-partial-closeup.png).

Source geometry:
- [Evolution renderer](../../ui/soulbound_hud/src/mana-evolution-renderer.js): seven `evolutionRunePaths` shapes.
- [HUD source](../../ui/soulbound_hud/soulbound-crystal-hud-preview.html): three `drawReferenceReserve` rune shapes.
- Painted gauge crown: optical Soul and Anchor traces, with the source visible in the sheet.

The exact imported points, optical trace points, definitions, image view regions and per-rune provenance are saved in [runes-v01.json](runes-v01.json). [build_dictionary.py](build_dictionary.py) produces the editable SVG. The PNG is an export of the same sheet, not an additional concept direction.
