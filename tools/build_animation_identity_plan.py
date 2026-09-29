#!/usr/bin/env python3
"""Prepare an inactive naming registry; never move source files or edit bindings."""
import json
from pathlib import Path
import re

from art_animation_naming import sha256
from art_asset_identity import identity_for_path, load_identities, original_path_for, validate_registry

ROOT = Path(__file__).resolve().parents[1]
REDUNDANT = {
    'Braced Hang Drop (1).fbx', 'Braced Hang Hop Left (1).fbx', 'Braced Hang Hop Right (1).fbx',
    'Braced Hang Hop Up (1).fbx', 'Braced Hang Shimmy.fbx', 'Braced Hang Shimmy(1).fbx',
    'Falling To Landing(1).fbx', 'Jump Braced Hang Wall.fbx', 'Jumping To Hanging (1).fbx',
}


def slug(value):
    value = re.sub(r'([a-z])([A-Z])', r'\1_\2', value).replace('→', '_to_')
    return re.sub(r'[^a-z0-9]+', '_', value.casefold()).strip('_')


def build_plan(root=ROOT):
    root = Path(root)
    registry = load_identities(root)
    configuration_path = root / 'tools/art_animation_classification.json'
    configuration = json.loads(configuration_path.read_text()) if configuration_path.exists() else {}
    paths = list((root / 'assets/animations').rglob('*'))
    paths += list((root / 'art_source/mixamo').glob('*.glb'))
    entries = []
    for path in sorted(paths):
        if not path.is_file() or path.suffix.lower() not in {'.fbx', '.tres', '.glb'} or path.is_symlink():
            continue
        relative = path.relative_to(root).as_posix()
        original = original_path_for(root, relative, registry)
        source_path = Path(original)
        if '/Mixamo/' in original and source_path.name in REDUNDANT:
            continue  # The separate Trash review retains their current paths.
        source_hash = sha256(path)
        subject = 'mixamo' if '/Mixamo/' in original else 'ual' if '/ual/' in original or original.startswith('art_source/mixamo/') else 'legacy_knight'
        purpose = slug(source_path.stem)
        if original == 'art_source/mixamo/crawling_ual.glb':
            purpose = 'crawl_retarget_reviewed'
        if path.suffix.lower() == '.tres' and 'type="AnimationLibrary"' in path.read_text(encoding='utf-8')[:150]:
            purpose += '_library'
        for override in configuration.get('clip_overrides', []):
            if override.get('path') == original and override.get('source_sha256') == source_hash and override.get('filename'):
                purpose = slug(override['filename'])
                break
        new_path = (source_path.parent / f'anim_{subject}_{purpose}_v01{path.suffix.lower()}').as_posix()
        entries.append(dict(id=identity_for_path(root, relative, registry), original_path=original,
            path=new_path, aliases=[original], source_sha256=source_hash))
    return validate_registry(dict(version=1, entries=entries))


if __name__ == '__main__':
    output = ROOT / 'tools/art_asset_identity_plan.json'
    data = build_plan()
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(data["entries"])} naming proposals in {output.relative_to(ROOT)}; no assets renamed.')
