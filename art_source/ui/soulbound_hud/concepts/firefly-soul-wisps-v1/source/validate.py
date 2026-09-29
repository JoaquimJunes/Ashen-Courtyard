"""Read-only artwork validation; writes only this reference pack's report."""
from pathlib import Path
import hashlib
import json
import re
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parent.parent
hud = root.parent.parent
manifest = json.loads((root / 'manifest.json').read_text())
names = ['01-empty', '02-burst', '03-gather', '04-settled-a', '05-settled-b']
mask = np.array(Image.open(root / 'source/hud-holdout.png').convert('RGB'))[...,0]
base = np.array(Image.open(root / 'review/fixed-hud-alignment-base.png').convert('RGB'))
stats = {}
for name in names:
    im = Image.open(root / f'images/{name}.png')
    assert im.size == (1280,720), (name, im.size)
    assert im.mode == 'RGB', (name, im.mode)
    a = np.array(im)
    assert a[395:470,415:495].max() == 0, f'{name}: center opening not black'
    assert a[:,840:].max() == 0, f'{name}: rightmost space not black'
    border = np.concatenate((a[:32].ravel(),a[-32:].ravel(),a[:,:32].ravel(),a[:,-32:].ravel()))
    assert border.max() == 0, f'{name}: clipping or contaminated outer margin'
    ys,xs = np.where(a.max(axis=2)>12)
    stats[name] = {'size':list(im.size),'mode':im.mode,'rgb_energy':int(a.sum()),
        'visible_bounds':None if len(xs)==0 else [int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())]}
    if name == '01-empty':
        assert a.max() == 0
    else:
        occluded = np.array(Image.open(root / f'review/{name}-occluded.png').convert('RGB'))
        assert occluded[mask==255].max() == 0, f'{name}: compositing holdout failed'
        comp = np.array(Image.open(root / f'review/{name}-aligned.png').convert('RGB'))
        assert np.array_equal(comp[mask==255],base[mask==255]), f'{name}: fixed HUD changed'
assert stats['02-burst']['rgb_energy'] > stats['03-gather']['rgb_energy'] > stats['04-settled-a']['rgb_energy']
assert stats['02-burst']['visible_bounds'][1] < stats['03-gather']['visible_bounds'][1] < stats['04-settled-a']['visible_bounds'][1]
idle_ratio = stats['05-settled-b']['rgb_energy'] / stats['04-settled-a']['rgb_energy']
assert abs(idle_ratio-1) < .02, idle_ratio
assert (root/'images/04-settled-a.png').read_bytes() != (root/'images/05-settled-b.png').read_bytes()
last_end = 2.5
last_image = 'images/01-empty.png'
for t in manifest['transitions']:
    assert t['first'] == last_image, t['id']
    assert abs(t['timeline_seconds'][0]-last_end)<1e-9
    assert abs(t['timeline_seconds'][1]-t['timeline_seconds'][0]-t['target_duration_seconds'])<1e-9
    for key in ('first','last','prompt_file'): assert (root/t[key]).is_file()
    assert (root/t['prompt_file']).read_text().strip() == t['prompt']
    last_end=t['timeline_seconds'][1]
    last_image=t['last']
assert last_image=='images/01-empty.png' and abs(last_end-8.7)<1e-9
html=(root/'START-HERE.html').read_text()
links=re.findall(r'(?:href|src)="([^"]+)"',html)
for link in links:
    if link.startswith(('https://','#')): continue
    assert (root/link).is_file(), link
assert '<script' not in html
original=json.loads((root/'source/existing-files-before.json').read_text())
changed=[name for name,old_hash in original.items() if not (hud/name).is_file() or hashlib.sha256((hud/name).read_bytes()).hexdigest()!=old_hash]
assert not changed, changed
report={'passed':True,'images':stats,'idle_b_to_a_energy_ratio':idle_ratio,
    'all_protected_hud_pixels_unchanged':True,'black_margin_pixels':32,
    'transition_pairs':len(manifest['transitions']),'guide_links_checked':len(links),
    'existing_hud_files_unchanged':len(original),'preview_integration':False,
    'visual_review':'Inspected individual poses and four-panel fixed-HUD alignment sheet; user artistic approval remains pending.'}
(root/'review/validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
