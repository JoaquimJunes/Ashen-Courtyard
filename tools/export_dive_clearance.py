"""Export real raised-gap Godot frames, preserving the geometry and measurement labels."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

source = Path('/tmp/dive-clearance-frames')
output = Path(__file__).resolve().parents[1] / 'docs/dive-clearance'
output.mkdir(exist_ok=True)
metadata = json.loads((source / 'metadata.json').read_text())
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 22)

def native(index):
    return Image.open(source / f'{index:03d}.png').convert('RGB')

for name, multiplier in [('normal', 1), ('slow', 4)]:
    indices = list(range(0, 73, 2))
    frames = [native(i).resize((960, 540), Image.Resampling.LANCZOS) for i in indices]
    # GIF ticks are 10 ms. Quantize cumulative time, not individual frame durations.
    ticks = [round(i * 100 * multiplier / 60) for i in indices + [indices[-1] + 2]]
    durations = [(b-a)*10 for a,b in zip(ticks,ticks[1:])]
    durations[0] += 600
    durations[-1] += 1000
    frames[0].save(output / f'raised-gap-{name}.gif', save_all=True,
                   append_images=frames[1:], duration=durations, loop=0, optimize=False)

def phase(n, fraction=0):
    items = [m for m in metadata if m['phase'] == n]
    return items[round((len(items)-1)*fraction)]

selected = [(phase(0, .5), 'Preparation'), (phase(1, 0), 'Takeoff'),
            (max(metadata, key=lambda m:m['rise']), 'Clearance'),
            (phase(2, 0), 'Actual landing'), (phase(2, .25), 'Grounded roll'),
            (phase(3, 0), 'Recovery')]
sheet = Image.new('RGB', (1280, 960), '#161e2b')
draw = ImageDraw.Draw(sheet)
for i, (m, label) in enumerate(selected):
    x, y = i%2*640, i//2*320
    draw.text((x+16,y+10), f'{label} / {m["time"]:.2f} s', fill='white', font=font)
    # Only crop surrounding empty space and review controls; keep all physical geometry.
    crop = native(m['frame']).crop((60,200,1250,570)).resize((640,199), Image.Resampling.LANCZOS)
    sheet.paste(crop, (x,y+62))
sheet.save(output / 'raised-gap-sequence.png')
(output / 'raised-gap-measurements.json').write_text(json.dumps(metadata, indent=2)+'\n')
print('Native raised-gap review exported to', output)
