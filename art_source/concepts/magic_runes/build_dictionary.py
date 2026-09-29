"""Build a static, editable reference sheet from approved HUD rune geometry.

No model calls, raster modification, network access, or runtime integration.
"""
from pathlib import Path
import base64
import html
import json

ROOT = Path(__file__).resolve().parent


def escape(value):
    return html.escape(str(value), quote=True)


def normalized_paths(strokes):
    points = [point for stroke in strokes for point in stroke]
    xs, ys = zip(*points)
    midx, midy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    scale = min(100 / (max(xs) - min(xs)), 120 / (max(ys) - min(ys)))
    return [' '.join(('M' if i == 0 else 'L') + f'{(x-midx)*scale:.3f},{(y-midy)*scale:.3f}'
                     for i, (x, y) in enumerate(stroke)) for stroke in strokes]


def build():
    data = json.loads((ROOT / 'runes-v01.json').read_text())
    assert len(data['runes']) == 12
    reference = ROOT / data['reference']
    encoded = base64.b64encode(reference.read_bytes()).decode()
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1500" viewBox="0 0 1920 1500">',
           '<title>The Twelve Runes — visual dictionary v01</title>',
           '<desc>Approved meaning-to-shape mapping, presented for visual review. Twelve symbols with definitions and unchanged crops of the mana gauge reference.</desc>',
           '<defs><image id="gauge" width="1264" height="712" href="data:image/png;base64,' + encoded + '"/></defs>',
           '<rect width="1920" height="1500" fill="#101116"/>',
           '<style>text{font-family:DejaVu Sans,sans-serif}.kicker{font-size:14px;letter-spacing:3px;fill:#bba1cf}.name{font-family:DejaVu Serif,serif;font-size:29px;fill:#f1e9dd}.meaning{font-size:17px;fill:#d2ccc5}.source{font-size:13px;fill:#a29aa9}.small{font-size:12px;letter-spacing:1px;fill:#b4a6bf}</style>',
           '<text x="64" y="56" class="kicker">ASHEN COURTYARD / ANCIENT RUNE LANGUAGE</text>',
           '<text x="60" y="116" font-family="DejaVu Serif,serif" font-size="52" fill="#f1e9dd">The Twelve Runes</text>',
           '<text x="64" y="153" font-size="18" fill="#bdb5c5">Meaning-to-shape mapping approved · Dictionary drawings awaiting review</text>',
           '<text x="1856" y="58" text-anchor="end" class="small">STATIC REFERENCE / V01</text>',
           '<line x1="64" x2="1856" y1="177" y2="177" stroke="#45404e"/>']
    for index, rune in enumerate(data['runes']):
        col, row = index % 4, index // 4
        x, y = 64 + col * 453, 205 + row * 371
        out += [f'<g transform="translate({x},{y})">',
                '<rect width="433" height="349" rx="10" fill="#1a1b22" stroke="#3b3743"/>',
                f'<text x="24" y="33" class="small">{index+1:02d} / {escape(rune["group"]).upper()}</text>',
                '<text x="318" y="33" text-anchor="middle" class="small">GAUGE</text>',
                '<g transform="translate(126,121)" fill="none" stroke="#c99cea" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">']
        for path in normalized_paths(rune['strokes']):
            out.append(f'<path d="{path}"/>')
        out += ['</g>', '<rect x="260" y="52" width="116" height="138" rx="7" fill="#101116" stroke="#49404f"/>']
        crop = ' '.join(str(v) for v in rune['reference_crop'])
        out.append(f'<svg x="268" y="60" width="100" height="122" viewBox="{crop}" preserveAspectRatio="xMidYMid meet"><use href="#gauge"/></svg>')
        out += [f'<text x="24" y="224" class="name">{escape(rune["name"])}</text>']
        for line_index, line in enumerate(rune['definition_lines']):
            out.append(f'<text x="24" y="254" class="meaning" dy="{line_index*24}">{escape(line)}</text>')
        out += ['<line x1="24" x2="409" y1="296" y2="296" stroke="#38323f"/>',
                f'<text x="24" y="320" class="source">{escape(rune["location"])}</text>', '</g>']
    out += ['<line x1="64" x2="1856" y1="1344" y2="1344" stroke="#45404e"/>',
            '<text x="64" y="1379" font-size="17" fill="#d7cddf">ESSENCE · what magic acts upon     ACTION · what magic does     STRUCTURE · how it is directed or held</text>',
            '<text x="64" y="1412" font-size="15" fill="#aaa1b3">Large glyphs: normalized drawings. Small panels: unchanged source crops. Soul and Anchor are optical traces.</text>',
            '<text x="64" y="1440" font-size="15" fill="#aaa1b3">Numbers are dictionary indices, not power levels. Circle grammar and cultural variants are developed separately.</text>',
            '</svg>']
    (ROOT / 'rune-dictionary-v01.svg').write_text('\n'.join(out), encoding='utf-8')


if __name__ == '__main__':
    build()
