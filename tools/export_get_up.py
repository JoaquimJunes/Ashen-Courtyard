"""Package native Godot captures; no generated poses or simulated physics."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/get-up'
DEST.mkdir(parents=True, exist_ok=True)


def clip(source, name, numbers):
    frames = [Image.open(source / f'{n:03}.png').convert('RGB') for n in numbers]
    # GIF stores centiseconds. Alternate 30/40 ms at 30 FPS to retain real timing.
    durations = [round((numbers[i + 1] - numbers[0]) * 100 / 60) * 10
                 - round((n - numbers[0]) * 100 / 60) * 10
                 for i, n in enumerate(numbers[:-1])] + [900]
    assert sum(durations[:-1]) == round((numbers[-1] - numbers[0]) * 100 / 60) * 10
    assert all(duration >= 10 for duration in durations)
    durations[0] += 300
    frames[0].save(DEST / name, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, optimize=False)


source = Path('/tmp/get-up-frames')
sheet = Image.new('RGB', (1440, 740), '#18242e')
draw = ImageDraw.Draw(sheet)
for row, kind in enumerate(['face_down', 'face_up']):
    clip(source / kind, kind + '.gif', list(range(0, 73, 2)))
    for col, n in enumerate([0, 14, 24, 36, 50, 72]):
        frame = Image.open(source / kind / f'{n:03}.png')
        sheet.paste(frame.crop((230, 90, 750, 465)).resize((240, 300)),
                    (col * 240, row * 370 + 36))
        draw.text((col * 240 + 10, row * 370 + 10),
                  f'{kind.replace("_", " ")} - {n / 60:.2f}s', fill='white')
sheet.save(DEST / 'pose-sheet.png')
(DEST / 'pose-measurements.json').write_text((source / 'metadata.json').read_text())

source = Path('/tmp/cliff-landing-frames/failed')
records = json.loads((source / 'metadata.json').read_text())
clip(source, 'fall-recovery.gif', list(range(0, len(records), 2)))
(DEST / 'fall-measurements.json').write_text(json.dumps(records, indent=2) + '\n')
print(DEST)
