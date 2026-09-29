#!/usr/bin/env python3
"""Build the UAL crawl with attached shoulders, preserving the immutable sources."""
import hashlib
import json
from pathlib import Path
import struct
from crawl_retarget import corrected_rotations

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb'
ORIGINAL = ROOT / 'assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx'
OUTPUT = ROOT / 'assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres'


def read_snapshot():
    data = SOURCE.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    document = json.loads(data[20:20 + length])
    binary = memoryview(data)[28 + length:]

    def accessor(index):
        entry = document['accessors'][index]
        view = document['bufferViews'][entry['bufferView']]
        assert entry['componentType'] == 5126 and 'sparse' not in entry
        width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[entry['type']]
        start = view.get('byteOffset', 0) + entry.get('byteOffset', 0)
        stride = view.get('byteStride', width * 4)
        return [struct.unpack_from('<' + 'f' * width, binary, start + i * stride)
                for i in range(entry['count'])]

    animation, = document['animations']
    channels = {}
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        target = channel['target']
        channels[target['node'], target['path']] = (
            [value[0] for value in accessor(sampler['input'])], accessor(sampler['output']),
            sampler.get('interpolation', 'LINEAR'))
    return data, document, channels


def build():
    data, document, channels = read_snapshot()
    animation, = document['animations']
    fitted_times, fitted = corrected_rotations(document, channels)
    lines = ['[gd_resource type="AnimationLibrary" format=3]', '',
             '[sub_resource type="Animation" id="Crawling"]',
             'resource_name = "Mixamo_Crawling_UAL"', 'length = 1.8', 'loop_mode = 1']
    for index, channel in enumerate(animation['channels']):
        target = channel['target']
        bone = document['nodes'][target['node']]['name']
        times, values, interpolation = channels[target['node'], target['path']]
        assert interpolation in ('LINEAR', 'STEP')
        if target['path'] == 'rotation' and target['node'] in fitted:
            times, values, interpolation = fitted_times, fitted[target['node']], 'LINEAR'
        kind = {'translation': 'position_3d', 'rotation': 'rotation_3d', 'scale': 'scale_3d'}[target['path']]
        keys = [number for time, value in zip(times, values) for number in (time, 1.0, *value)]
        lines += [f'tracks/{index}/type = "{kind}"', f'tracks/{index}/imported = true',
                  f'tracks/{index}/enabled = true',
                  f'tracks/{index}/path = NodePath("Armature/Skeleton3D:{bone}")',
                  f'tracks/{index}/interp = {1 if interpolation == "LINEAR" else 0}', f'tracks/{index}/loop_wrap = true',
                  f'tracks/{index}/keys = PackedFloat32Array({", ".join(format(x, ".9g") for x in keys)})']
    lines += ['metadata/source_clip = "Crawling"',
              'metadata/source_scene = "res://art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb"',
              f'metadata/source_sha256 = "{hashlib.sha256(data).hexdigest()}"',
              'metadata/original_source = "res://assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx"',
              f'metadata/original_sha256 = "{hashlib.sha256(ORIGINAL.read_bytes()).hexdigest()}"',
              'metadata/retargeted = true', 'metadata/retarget_correction = "attached_shoulders_v1"',
              'metadata/reference_speed = 1.0', '',
              '[resource]', '_data = { &"crawl": SubResource("Crawling") }', '']
    OUTPUT.write_text('\n'.join(lines))
    print(f'Extracted {len(animation["channels"])} UAL pose tracks: {OUTPUT}')


if __name__ == '__main__':
    build()
