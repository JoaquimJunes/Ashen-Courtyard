"""Readable animation labels backed by source names or fingerprint-pinned review.

Labels never become animation bindings. Unknown transition states stay unknown.
"""
from copy import deepcopy
import hashlib
import os
from pathlib import Path
import re


def sha256(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return ''


def readable(value):
    value = re.sub(r'([a-z])([A-Z])', r'\1 \2', str(value))
    return re.sub(r'\s+', ' ', value.replace('_', ' ').replace('-', ' ')).strip()


def original_path(parent):
    return next(iter(parent.get('original_paths', [])), parent['path'])


def _state(value):
    value = readable(value).strip()
    key = value.casefold()
    names = {'free hang': 'Free hanging', 'freehang': 'Free hanging', 'braced hang': 'Braced hanging',
             'hanging': 'Hanging', 'hang': 'Hanging', 'jump': 'Jumping', 'jumping': 'Jumping',
             'fall': 'Falling', 'falling': 'Falling', 'crouch': 'Crouching', 'stand': 'Standing'}
    return names.get(key, value[:1].upper() + value[1:])


def naming_fields(name, parent, descriptor, overrides=(), source_hash=''):
    path = original_path(parent)
    aliases = list(dict.fromkeys([path, parent['path'], *parent.get('original_paths', [])]))
    generic = name in {'mixamo_com', 'Animation', 'Take 001', 'Take 01', ''}
    source = Path(path).stem if generic else name
    title = readable(source)
    if not title:
        title = 'Unnamed animation'
    title = title[:1].upper() + title[1:]
    match = re.fullmatch(r'(?:regular sword|sword regular) ([a-z])(?: (rec|recovery))?', title, re.I)
    if match:
        title = f'Sword · Regular attack {match[1].upper()}' + (' recovery' if match[2] else '')
    elif re.fullmatch(r'sword heavy(?: attack)?', title, re.I):
        title = 'Sword · Heavy attack'
    elif re.fullmatch(r'sword idle', title, re.I):
        title = 'Sword · Idle'
    loop = descriptor.get('loop') is True or descriptor.get('loop') in {1, 2}
    if loop and not re.search(r'\bloop\b', title, re.I):
        title += ' · Loop'
    start, end, steps = '', '', []
    transition = re.split(r'\s+to\s+', readable(source), flags=re.I)
    status = 'source_name'
    evidence = [f'Original {"filename" if generic else "clip name"}: {source}']
    if len(transition) > 1:
        steps = [_state(step) for step in transition if step.strip()]
        if steps:
            start, end = steps[0], steps[-1]
        status = 'needs_review'  # The name alone cannot verify intermediate motion.
    elif re.search(r'\b(enter|exit|start|end|drop|landing|land|climb|mantle)\b', readable(source), re.I) and not loop:
        status = 'needs_review'
    if generic and source.casefold() in {'animation', 'take 001', 'take 01'} or not name:
        status = 'needs_review'
    fields = dict(title=title, transition_steps=steps, start_state=start, end_state=end,
        naming_status=status, naming_evidence=evidence,
        original_names=list(dict.fromkeys([name, Path(path).stem])), original_paths=aliases)
    for override in overrides:
        if override.get('path') not in aliases or override.get('name') != name:
            continue
        override = dict(override)
        for short, full in {'start': 'start_state', 'end': 'end_state',
                            'steps': 'transition_steps', 'evidence': 'naming_evidence'}.items():
            if short in override and full not in override:
                override[full] = override[short]
        naming_keys = {'title', 'start_state', 'end_state', 'transition_steps', 'naming_status', 'naming_evidence'}
        if not naming_keys.intersection(override):
            continue
        if override.get('source_sha256') != source_hash or not source_hash:
            fields['naming_status'] = 'needs_review'
            fields['naming_evidence'].append('The saved naming review does not match the current source fingerprint.')
            continue
        explicit = {key: deepcopy(value) for key, value in override.items() if key in naming_keys}
        if not all(isinstance(explicit.get(key, ''), str) for key in ('title', 'start_state', 'end_state')):
            raise ValueError('Animation naming override title/states must be text: ' + path)
        for key in ('transition_steps', 'naming_evidence'):
            if key in explicit and (not isinstance(explicit[key], list) or
                    not all(isinstance(value, str) and value.strip() for value in explicit[key])):
                raise ValueError('Animation naming override needs a list of nonempty strings: ' + key)
        if explicit.get('naming_status', status) not in {'verified', 'source_name', 'needs_review'}:
            raise ValueError('Unknown animation naming review status: ' + path)
        if explicit.get('naming_status') == 'verified' and not explicit.get('naming_evidence'):
            raise ValueError('Verified animation naming requires recorded evidence: ' + path)
        fields.update(explicit)
        if loop and 'title' in explicit and not re.search(r'\bloop\b', fields['title'], re.I):
            fields['title'] += ' · Loop'
    return fields


def apply_duplicate_audit(root, entries, audit):
    """Attach read-only evidence; stale or ambiguous groups cannot queue files."""
    by_path, hashes = {}, {}
    for entry in entries:
        entry.update(duplicate_group=None, duplicate_status='', duplicate_keeper_id='',
            duplicate_evidence=[], duplicate_file_eligible=False, duplicate_reason='',
            duplicate_references=[], duplicate_runtime_references=[])
        for alias in dict.fromkeys([entry['path'], *entry.get('original_paths', [])]):
            by_path.setdefault(alias, []).append(entry)
    if not audit:
        return
    if not isinstance(audit, dict) or audit.get('version') != 1 or not isinstance(audit.get('groups'), list):
        raise ValueError('Invalid animation duplicate audit')
    for group in audit['groups']:
        if not isinstance(group.get('id'), str) or not isinstance(group.get('members'), list):
            raise ValueError('Animation duplicate audit group requires ID and members')
        members = group['members']
        if not all(isinstance(path, str) for path in members):
            raise ValueError('Animation duplicate audit members must be original paths')
        clips = [entry for path in members for entry in by_path.get(path, [])]
        keeper = by_path.get(group.get('keeper'), [])
        status = group.get('status', 'candidate')
        if status not in {'verified_duplicate', 'candidate', 'distinct_variant', 'derived'}:
            raise ValueError('Unknown animation duplicate audit status')
        pinned = True
        for member in members:
            matches = by_path.get(member, [])
            if not matches:
                pinned = False
            for entry in matches:
                path = entry['path']
                if path not in hashes:
                    hashes[path] = sha256(Path(root) / path)
                if not hashes[path] or hashes[path] != group.get('member_sha256', {}).get(member):
                    pinned = False
        unique = len(set(members)) == len(members) and all(len(by_path.get(path, [])) == 1 for path in members)
        variants = {(entry.get('rig', ''), entry.get('motion_mode', '')) for entry in clips}
        names = {entry.get('source_clip', {}).get('name', '') for entry in clips}
        durations = {entry.get('source_clip', {}).get('duration') for entry in clips
                     if entry.get('source_clip', {}).get('duration') is not None}
        comparable = len(names) == 1 and '' not in names and len(durations) <= 1
        eligible = bool(pinned and unique and len(keeper) == 1 and group.get('keeper') in members
            and len({entry.get('parent_id', entry['path']) for entry in clips}) == len(members)
            and comparable and len(variants) <= 1 and status == 'verified_duplicate'
            and group.get('duplicate_file_eligible') and len(members) >= 2)
        evidence = group.get('evidence', [])
        if not isinstance(evidence, list) or not all(isinstance(value, str) for value in evidence):
            raise ValueError('Animation duplicate evidence must be a string list')
        eligible = eligible and bool(evidence)
        reason = group.get('reason', '')
        if not pinned:
            status = 'candidate'
            reason = 'Source files changed or are missing; duplicate evidence needs to be checked again.'
        elif not unique and status == 'verified_duplicate':
            status = 'candidate'
            reason = 'Whole-file removal is unavailable for multi-clip or ambiguous animation files.'
        elif len(variants) > 1:
            status = 'distinct_variant'
            reason = 'Rig or root-motion variants must remain separate; duplicate removal is unavailable.'
        elif not comparable and status == 'verified_duplicate':
            status = 'candidate'
            reason = 'Exact clip names or timing differ or are unavailable; keep clips separate for review.'
        for entry in clips:
            if entry['duplicate_group'] and entry['duplicate_status'] in {'candidate', 'verified_duplicate'} and status == 'distinct_variant':
                entry['duplicate_evidence'] += [item for item in evidence if item not in entry['duplicate_evidence']]
                continue
            entry.update(duplicate_group=group['id'], duplicate_status=status,
                duplicate_keeper_id=keeper[0]['id'] if len(keeper) == 1 else '',
                duplicate_evidence=deepcopy(evidence), duplicate_file_eligible=eligible,
                duplicate_reason=reason)
    _reference_annotations(root, entries)


def _reference_annotations(root, entries):
    """Report known textual references, with final dependency checks left to Trash."""
    root = Path(root)
    candidates = [entry for entry in entries if entry.get('duplicate_group')]
    paths = {entry['path'] for entry in candidates}
    if not paths:
        return
    refs = {path: set() for path in paths}
    runtime = {path: set() for path in paths}
    aliases = {path: {path} for path in paths}
    for entry in candidates:
        aliases[entry['path']].update(entry.get('original_paths', []))
    patterns = {path: re.compile(r'[\"\']res://(?:' + '|'.join(re.escape(alias) for alias in values) + r')[\"\']')
                for path, values in aliases.items()}
    skipped = {'.git', '.godot', '.artifacts', 'artifacts', 'node_modules', 'vendor',
               '__pycache__', '.cache', '.pytest_cache'}
    failed = False
    for directory, directories, filenames in os.walk(root, followlinks=False):
        directory = Path(directory)
        directories[:] = [name for name in directories if name not in skipped
            and not (directory / name).is_symlink() and (directory / name) != root / 'docs/tracker']
        for name in filenames:
            file = directory / name
            if file.is_symlink() or file.suffix.casefold() not in {'.gd', '.tscn', '.tres', '.godot', '.gdshader', '.html', '.md', '.css', '.js'}:
                continue
            relative = file.relative_to(root).as_posix()
            try:
                content = file.read_text(encoding='utf-8', errors='replace')
            except OSError:
                failed = True
                continue
            for path in paths:
                if relative == path:
                    continue
                if patterns[path].search(content):
                    runtime[path].add(relative)
                    refs[path].add(relative)
                elif any(alias in content or Path(alias).name in content for alias in aliases[path]):
                    refs[path].add(relative)
    for entry in candidates:
        entry['duplicate_references'] = sorted(refs[entry['path']])
        entry['duplicate_runtime_references'] = sorted(runtime[entry['path']])
        if runtime[entry['path']] or failed:
            entry['duplicate_file_eligible'] = False
            entry['duplicate_reason'] = ('Referenced by Godot project resources; retain this source.'
                if runtime[entry['path']] else 'Some project references could not be checked; review is required.')
