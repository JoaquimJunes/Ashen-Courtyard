"""Assemble native Godot review frames; requires Pillow only for this export tool."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

SOURCE = Path('/tmp/dodge-preview-frames')
OUTPUT = Path(__file__).resolve().parents[1] / 'docs'
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
TITLE = ImageFont.truetype(FONT, 24)
SMALL = ImageFont.truetype(FONT, 17)
BACKGROUND = '#161e2b'
OUTPUT.mkdir(exist_ok=True)


def frame_image(frame, speed):
    result = Image.new('RGB', (960, 500), BACKGROUND)
    native = Image.open(SOURCE / f'{frame:03d}.png')
    result.paste(native.crop((220, 180, 1180, 590)), (0, 60))
    text = ImageDraw.Draw(result)
    text.text((20, 14), f'FORWARD DODGE  /  {speed}', font=TITLE, fill='white')
    text.text((20, 476), 'Shared playable character  |  0.25 m rise  |  5.5 m travel', font=SMALL, fill='#c4d4e6')
    return result


# GIF frame times are multiples of 10 ms: alternate durations to preserve timing.
for name, speed, timing in [('normal', 'Normal speed', (30, 30, 40)),
                            ('slow', 'Quarter speed (0.25x)', (130, 130, 140))]:
    frames = [frame_image(i, speed) for i in range(0, 71, 2)]
    durations = [timing[i % 3] for i in range(len(frames))]
    durations[0] += 500
    durations[-1] += 900
    frames[0].save(OUTPUT / f'dodge-preview-{name}.gif', save_all=True,
                   append_images=frames[1:], duration=durations, loop=0, optimize=False)

sheet = Image.new('RGB', (1200, 680), BACKGROUND)
metadata = json.loads((SOURCE / 'metadata.json').read_text())
def nearest_phase(phase, fraction=0.5):
    frames = [f for f in metadata if f['phase'] == phase]
    return frames[min(len(frames)-1, round((len(frames)-1)*fraction))]
selected = [(nearest_phase(0,0.5), 'Bend and lean'),
            (nearest_phase(1,0), 'Takeoff'),
            (max(metadata, key=lambda f:f['rise']), 'Extended dive / apex'),
            (nearest_phase(2,0), 'Ground contact'),
            (nearest_phase(2,0.45), 'Grounded roll'),
            (nearest_phase(3,0), 'Recovery')]
# The fixed orthographic camera projects one metre to ~106 pixels at 720p.
samples = [(f['frame'], label, 423 + 106*f['travel']) for f,label in selected]

for i, (frame, label, center) in enumerate(samples):
    native = Image.open(SOURCE / f'{frame:03d}.png')
    crop = native.crop((center-200, 185, center+200, 485))
    x, y = (i % 3)*400, (i // 3)*340
    sheet.paste(crop, (x, y+40))
    ImageDraw.Draw(sheet).text((x+16, y+12), label, font=SMALL, fill='white')
sheet.save(OUTPUT / 'dodge-preview-poses.png')
print('Exported two looping GIFs and the contact sheet to', OUTPUT)
