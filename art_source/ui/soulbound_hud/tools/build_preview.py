"""Embed local artwork and export the review as one offline HTML file (stdlib only)."""
from __future__ import annotations

import base64
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "soulbound-crystal-hud-preview.html"


def main() -> None:
    fragment = SOURCE.read_text(encoding="utf-8")
    for name in ("mana-evolution", "mana-evolution-renderer"):
        code = (ROOT / "src" / f"{name}.js").read_text(encoding="utf-8").rstrip()
        start, end = f"// EMBED_{name}_START", f"// EMBED_{name}_END"
        fragment, count = re.subn(
            re.escape(start) + r"[\s\S]*?" + re.escape(end),
            lambda _: f"{start}\n{code}\n    {end}", fragment,
        )
        if count != 1:
            raise ValueError(f"Expected exactly one {name} embedding slot, found {count}")
    for filename, mime in (
        ("starting-frame-v1-lossless.webp", "image/webp"),
        ("courtyard-preview.jpg", "image/jpeg"),
    ):
        encoded = base64.b64encode((ROOT / "assets" / filename).read_bytes()).decode("ascii")
        fragment, count = re.subn(
            rf"data:{re.escape(mime)};base64,[A-Za-z0-9+/=]+",
            f"data:{mime};base64,{encoded}",
            fragment,
        )
        if count != 1:
            raise ValueError(f"Expected exactly one embedded {mime} asset, found {count}")
    if len(fragment.encode("utf-8")) > 1_000_000:
        raise ValueError("Inline source exceeds 1 MB; optimize assets before rebuilding")
    if fragment != SOURCE.read_text(encoding="utf-8"):
        SOURCE.write_text(fragment, encoding="utf-8")
    subprocess.run(
        [sys.executable, str(ROOT / "tools/vendor/visualize/scripts/render.py"),
         str(SOURCE), str(ROOT / "index.html"), "--title", "Ashen Courtyard — Soulbound HUD", "--force"],
        check=True,
    )


if __name__ == "__main__":
    main()
