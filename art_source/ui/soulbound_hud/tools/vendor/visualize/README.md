# Standalone exporter provenance

`scripts/render.py` and `assets/visualize.css` are copied from the Codex
Visualize skill, version 1.0.29, on 28 September 2026. The renderer is unchanged.
It preserves the fragment inside a sandboxed standalone HTML document.

`assets/visualize.html` intentionally contains only the fragment placeholder.
The HUD uses its own controls, drawing, styles, and embedded images; it does not
use the original kit's tooltip, tab, or icon helpers. Omitting those helpers
removes their external CDN scripts and makes this export work offline.

The package needs Python's standard library to rebuild and no Codex installation.
The generated `index.html` needs neither Python nor Node to open.
