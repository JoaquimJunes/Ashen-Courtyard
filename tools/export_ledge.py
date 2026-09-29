#!/usr/bin/env python3
"""Package Godot's actual character capture; no generated or reconstructed motion."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
blocked = '--blocked' in sys.argv
frames = Path('/tmp/ledge-blocked-frames' if blocked else '/tmp/ledge-frames')
name = 'ledge-blocked' if blocked else 'ledge-pull-up'
out = root / 'docs/ledge-grab'
out.mkdir(parents=True, exist_ok=True)
records = json.loads((frames / 'metadata.json').read_text())
selected = records[::2]
images = [Image.open(frames / f'{record["frame"]:03}.png').convert('RGB') for record in selected]
# GIF delays use centiseconds: alternate 30/40 ms rather than rounding all to 30.
times = [round(record['time'] * 100) * 10 for record in selected]
durations = [max(10, b-a) for a,b in zip(times,times[1:])] + [500]
images[0].save(out/f'{name}.gif', save_all=True, append_images=images[1:],
               duration=durations, loop=0, optimize=True)
(out/f'{name}-capture.json').write_text(json.dumps(records,indent=2)+'\n')
if blocked:
    print(out/f'{name}.gif')
    raise SystemExit(0)
choices = [('Jump', next(r for r in records if r['status']=='idle')),
           ('Catch', next(r for r in records if r['status']=='grab')),
           ('Hang', next(r for r in records if r['status']=='hang')),
           ('Lift', next(r for r in records if r['status']=='mantle' and r['phase']==1)),
           ('Knee over', next(r for r in records if r['status']=='mantle' and r['phase']==2)),
           ('Standing', next(r for r in records if r['reason']=='completed'))]
sheet = Image.new('RGB',(1200,650),'#18242e')
draw = ImageDraw.Draw(sheet)
for i,(label,record) in enumerate(choices):
    image = Image.open(frames/f'{record["frame"]:03}.png').crop((110,75,850,465))
    image.thumbnail((400,280))
    x,y = i%3*400,i//3*325
    sheet.paste(image,(x,y+35))
    draw.text((x+16,y+12),label,fill='white')
sheet.save(out/'ledge-poses.png')
print(out/f'{name}.gif')
