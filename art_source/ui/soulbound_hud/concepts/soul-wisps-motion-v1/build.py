"""Build the isolated motion reference; never writes the interactive HUD preview."""
from pathlib import Path
import argparse
import base64

ROOT = Path(__file__).resolve().parent
HUD = ROOT.parent.parent

def build(destination):
    content = (ROOT / 'reference.html').read_text()
    for slot, filename in [('TIMELINE', 'timeline.js'), ('DRAWING', 'drawing.js'), ('PLAYER', 'player.js')]:
        content = content.replace('// EMBED_' + slot, (ROOT / filename).read_text())
    art = base64.b64encode((HUD / 'assets/starting-frame-v1-lossless.webp').read_bytes()).decode()
    content = content.replace('EMBED_FRAME', 'data:image/webp;base64,' + art)
    assert len(content.encode()) < 1_000_000
    assert 'EMBED_' not in content
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content)
    print(f'Built {destination} ({len(content.encode()):,} bytes)')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    build(parser.parse_args().destination)
