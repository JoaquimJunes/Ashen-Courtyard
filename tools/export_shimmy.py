#!/usr/bin/env python3
"""Package native Godot character captures, preserving their recorded timing."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
out = root/'docs/ledge-shimmy'
out.mkdir(parents=True,exist_ok=True)
for kind in ['outside','inside']:
    source = Path(f'/tmp/shimmy-{kind}-frames')
    records = json.loads((source/'metadata.json').read_text())
    turning = [r for r in records if r['reason']==f'{kind}_corner']
    if not turning:
        raise SystemExit(f'{kind}: capture contains no corner traversal; render it again before exporting.')
    selected = records[::2]
    frames = [Image.open(source/f'{r["frame"]:03}.png').convert('RGB') for r in selected]
    times = [round(r['time']*100)*10 for r in selected]
    durations = [max(10,b-a) for a,b in zip(times,times[1:])] + [500]
    frames[0].save(out/f'{kind}.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=True)
    samples = [turning[round((len(turning)-1)*t)] for t in [0,.33,.66,1]]
    sheet = Image.new('RGB',(1200,620),'#18242e')
    draw = ImageDraw.Draw(sheet)
    for i,r in enumerate(samples):
        image = Image.open(source/f'{r["frame"]:03}.png').crop((100,75,860,465))
        image.thumbnail((600,280))
        x,y = i%2*600,i//2*310
        sheet.paste(image,(x,y+30))
        draw.text((x+14,y+10),f'{kind.title()} corner / {r["time"]:.2f}s',fill='white')
    sheet.save(out/f'{kind}-poses.png')
    (out/f'{kind}-capture.json').write_text(json.dumps(records,indent=2)+'\n')
    print(out/f'{kind}.gif')
