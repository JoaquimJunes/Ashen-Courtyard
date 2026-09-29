"""Assemble native Godot frames; does not synthesize animation or physics."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path('/tmp/ground-roll-frames')
DEST = ROOT / 'docs/ground-rolls'
DEST.mkdir(parents=True, exist_ok=True)
records = json.loads((SOURCE / 'metadata.json').read_text())
assert len(records) == 183
assert all(row['grounded'] and abs(row['rise']) < 0.01 for row in records)
frames = []
durations = []
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 22)
sheet = Image.new('RGB', (1920, 700), '#18242e')
draw = ImageDraw.Draw(sheet)
draw.text((20, 14), 'ACTUAL PLAYER  /  LEFT, RIGHT, BACK  /  0.70 s  /  NO PHYSICAL HOP', font=font, fill='white')
for row, clip in enumerate(['left', 'right', 'back']):
    assert len(list((SOURCE / clip).glob('*.png'))) == 61
    for index in range(0, 61, 2):
        frame = Image.open(SOURCE / clip / f'{index:03}.png').convert('RGB')
        frames.append(frame)
        durations.append(300 if index in (0, 60) else (30 if index % 6 else 40))
    for column, index in enumerate([0, 8, 17, 25, 34, 42]):
        frame = Image.open(SOURCE / clip / f'{index:03}.png').convert('RGB')
        # Remove captions for the compact sheet; keep the full fixed camera in
        # the GIF so the ground grid makes actual displacement visible.
        frame = frame.crop((0, 75, 960, 465)).resize((320, 130), Image.Resampling.LANCZOS)
        x, y = column * 320, 82 + row * 205
        sheet.paste(frame, (x, y))
        draw.text((x + 10, y + 134), f'{index / 60:.2f}s', font=font, fill='#c5d8e4')
    draw.text((18, 52 + row * 205), clip.upper(), font=font, fill='#9ee2e0')
frames[0].save(DEST / 'ground-rolls.gif', save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=False)
sheet.save(DEST / 'ground-rolls.png')
(DEST / 'measurements.json').write_text(json.dumps(records, indent=2) + '\n')
print(DEST)
