"""Verify the saved editable copy independently of the rendering process."""
import bpy
import json
import os
from pathlib import Path
import numpy as np

OUT=Path(__file__).resolve().parent
# Reuse just the source signature function, with no material or pose mutations.
prefix=(OUT/'render_preview.py').read_text().split('baseline=json.loads')[0]
exec(compile(prefix,str(OUT/'render_preview.py'),'exec'))
baseline=json.loads((OUT/'baseline.json').read_text())
assert signature()==baseline['signatures'],'Saved geometry/UV/rig mismatch'
im=bpy.data.images.get('Protagonist_BaseColor_512')
assert im and tuple(im.size)==(512,512) and im.packed_file
external=bpy.data.images.load(str(OUT/'Protagonist_BaseColor_512.png'),check_existing=False)
packed_pixels=np.array(im.pixels[:]); external_pixels=np.array(external.pixels[:])
assert np.max(abs(packed_pixels-external_pixels))<1e-6,'Packed image differs from delivered PNG'
for m in bpy.data.objects['Mannequin'].data.materials:
    assert m.node_tree.nodes['Paint Base Color'].interpolation=='Closest'
    assert m.node_tree.nodes['UV Map'].uv_map=='CharacterPaint'
assert bpy.data.objects['Armature'].data.pose_position=='REST'
result=json.loads((OUT/'validation.json').read_text())
result.update({'saved_copy_reopened':True,'packed_texture_matches_png':True,'source_pose_retained':'REST','animation_actions_retained':len(bpy.data.actions)})
(OUT/'validation.json').write_text(json.dumps(result,indent=2))
print('SAVED_COPY_VERIFIED',json.dumps(result),flush=True)
os._exit(0)
