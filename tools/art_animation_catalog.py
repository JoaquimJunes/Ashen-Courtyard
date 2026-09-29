"""Stable, classified animation-clip views over unchanged Art Book source files."""
from collections import Counter
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re

from art_catalog_metadata import attributes, read_json, read_text, SECTIONS, STRING
from art_preview_metadata import Fingerprints, local_path, unavailable
from art_animation_naming import naming_fields, original_path, sha256, apply_duplicate_audit

TAXONOMY = 'tools/art_animation_taxonomy.json'
CLASSIFICATION = 'tools/art_animation_classification.json'
CATEGORY_SLUGS = {'Combat': 'combat', 'Movement': 'movement', 'Interactions': 'interactions',
                  'Poses & utilities': 'poses-utilities', 'Unclassified': 'unclassified'}

# Every default uses literal action-name evidence; unsupported semantic guesses
# (Consume = Healing, for example) are intentionally absent.
TAG_RULES = {
 'Sword attack': r'\bsword\b.*\b(attack|regular|heavy|combo|slash|stab)\b',
 'Bow aiming': r'\bbow\b.*\b(aim|aiming|draw|release)\b|\b(aim|aiming|draw)\b.*\b(bow|arrow)\b',
 'Stealth': r'\b(stealth|sneak|sneaking)\b',
 'Sword running': r'\b(run|running|sprint)\b.*\bsword\b|\bsword\b.*\b(run|running|sprint)\b',
 'Blocking': r'\b(block|blocking)\b', 'Parrying': r'\b(parry|parrying)\b',
 'Throwing': r'\b(throw|throwing)\b', 'Hit reaction': r'\bhit\b',
 'Stunned': r'\b(stun|stunned)\b', 'Spell casting': r'\b(spell|spellcasting|magic)\b',
 'Healing': r'\b(heal|healing)\b', 'Death': r'\b(death|dying)\b',
 'Aerial attack': r'\b(attack|slash|slam)\b.*\b(jump|jumping|aerial)\b|\b(jump|jumping|aerial)\b.*\b(attack|slash|slam)\b',
 'Weapon equip': r'\b(equip|equipping)\b|\bwithdrawing\b.*\bsword\b',
 'Weapon stow': r'\b(sheath|sheathing|holster|holstering)\b|\bdisarm\b.*\bbow\b',
 'Locomotion': r'\b(walk|walking|run|running|jog|jogging|sprint|sprinting|locomotion)\b',
 'Crouching': r'\b(crouch|crouching)\b', 'Crawling': r'\b(crawl|crawling)\b',
 'Climbing': r'\b(climb|climbing|mantle|mantling)\b', 'Swimming': r'\b(swim|swimming)\b',
 'Jumping': r'\b(jump|jumping)\b', 'Running jump': r'\b(run|running)\b.*\b(jump|jumping)\b',
 'Free fall': r'\bfree\s*fall\b|\bfreefall\b', 'Sliding': r'\b(slide|sliding)\b',
 'Free hanging': r'\bfree\s*hang(?:ing)?\b|\bfreehang\b',
 'Braced hanging': r'\bbraced\s*hang(?:ing)?\b',
 'Mantling': r'\b(mantle|mantling)\b', 'Falling': r'\b(fall|falling|freefall)\b',
 'Landing': r'\b(land|landing)\b',
 'Dodging': r'\b(dodge|dodging|roll)\b', 'Dancing': r'\b(dance|dancing)\b',
 'Item pickup': r'\bpick\s*up\b|\bpickup\b', 'Chest opening': r'\bchest\b.*\b(open|opened|opening)\b',
 'Emotes': r'\b(cheering|waving|yes|taunt|talking|flexing|emote|roaring)\b',
 'Horse mounting': r'\bhorse\b.*\b(mount|mounting)\b|\b(mount|mounting)\b.*\bhorse\b',
 'Carrying': r'\b(carry|carrying)\b', 'Pushing': r'\b(push|pushing)\b(?!\s*ups\b)',
 'Sitting': r'\b(sit|sitting)\b', 'Item use': r'\bconsume\b|\buse\s*item\b',
 'Work': r'\b(work|working|farm|harvest|plant|watering|chopping|dig|digging|fishing|hammer|hammering|pickaxe|pickaxing|saw|sawing|lockpick|lockpicking|fixing)\b',
}


def words(value):
    value = re.sub(r'([a-z])([A-Z])', r'\1 \2', value)
    value = re.sub(r'([A-Za-z])([0-9])', r'\1 \2', value)
    return re.sub(r'[^a-z0-9]+', ' ', value.lower()).strip()


def clip_id(parent_id, exact_name):
    return 'art:clip:' + hashlib.sha256((parent_id + '\0' + exact_name).encode()).hexdigest()[:24]


def load_taxonomy(root):
    path = root / TAXONOMY
    if not path.is_file():
        path = Path(__file__).with_name(Path(TAXONOMY).name)
    taxonomy = read_json(path)
    if not isinstance(taxonomy, dict) or taxonomy.get('version') != 1 or taxonomy.get('categories') != list(CATEGORY_SLUGS):
        raise ValueError('Invalid animation taxonomy categories or version')
    tags = taxonomy.get('tags')
    if not isinstance(tags, list) or len(tags) != len(set(tags)) or set(tags) != set(TAG_RULES):
        raise ValueError('Invalid controlled animation tags')
    if set(t for values in taxonomy.get('category_tags', {}).values() for t in values) != set(tags):
        raise ValueError('Animation category/tag mapping is incomplete')
    return taxonomy


def classify(name, path, taxonomy):
    evidence_name = Path(path).stem if name == 'mixamo_com' else name
    if path == 'art_source/mixamo/crawling_ual.glb' and name == 'Animation':
        evidence_name = 'Crawling'
    normalized = words(evidence_name)
    tags = [tag for tag in taxonomy['tags'] if re.search(TAG_RULES[tag], normalized)]
    if path.endswith('/Rig_Medium_Tools.glb') and normalized == 'chop':
        tags.append('Work')
    categories = [category for category, values in taxonomy['category_tags'].items() if any(tag in values for tag in tags)]
    if re.search(r'\b(sword|shield|melee|punch|kick|ranged|pistol|rifle|bow|fight|strangled|swiping|zombie\s*scratch)\b', normalized):
        categories.append('Combat')
    if re.search(r'\binteract\b', normalized): categories.append('Interactions')
    if re.search(r'\b(t\s*pose|pose|idle|spawn|holding)\b', normalized) and not categories:
        categories.append('Poses & utilities')
    if not categories: categories = ['Unclassified']
    return [category for category in taxonomy['categories'] if category in categories], tags


def source_provenance(root, path):
    """Read serialized source metadata, matching library keys to subresources."""
    if not path.endswith('.tres'):
        return {}
    text = read_text(local_path(root, path))
    headers = list(SECTIONS.finditer(text))
    resources, aliases = {}, {}
    for index, match in enumerate(headers):
        header = match.group(1)
        body = text[match.end():headers[index + 1].start() if index + 1 < len(headers) else len(text)]
        attrs = attributes(header)
        if attrs.get('type') == 'Animation' or header == 'resource':
            fields = {}
            for field in ('source_scene', 'source_clip', 'source_root_motion'):
                value = re.search(r'^metadata/' + field + r'\s*=\s*("[^"\n]*"|true|false)', body, re.M)
                if value: fields[field] = json.loads(value.group(1))
            if attrs.get('id'): resources[attrs['id']] = fields
            elif fields: resources[''] = fields
        if header == 'resource':
            for name, reference in re.findall(r'&?(' + STRING + r')\s*:\s*SubResource\(' + r'(' + STRING + r')\)', body):
                aliases[json.loads(name)] = json.loads(reference)
    return {name: resources.get(reference, {}) for name, reference in aliases.items()} if aliases else {'': resources.get('', {})}


def library(path):
    if '/ual2/' in path and 'quaternius' in path: return 'UAL 2'
    if path.endswith('/UAL1_Standard.glb'): return 'UAL 1'
    if '/Mixamo/' in path or path.startswith('art_source/mixamo/') or path.endswith('/mixamo_crawling.tres'): return 'Mixamo'
    if '/kaykit/' in path: return 'KayKit'
    if '/fullplate_knight/' in path: return 'Fullplate Knight'
    if '/dysfunctional_psx_starter/' in path: return 'Dysfunctional PSX Starter'
    if '/psx_going_medieval/' in path: return 'PSX Going Medieval'
    if '/quaternius/' in path: return 'Quaternius'
    return 'Project resources' if path.startswith('assets/animations/') else 'Unknown'


def rig_name(parent):
    path = original_path(parent)
    preview = parent.get('preview', {})
    if ('/quaternius/UAL1_' in path or '/quaternius/ual2/UAL2_' in path
            or path.startswith('assets/animations/ual/') or preview.get('provenance', {}).get('target_rig') == 'ual1_65_v1'
            or path == 'art_source/mixamo/crawling_ual.glb'):
        return 'UAL 65-bone'
    if '/Rig_Medium/' in path: return 'KayKit Medium'
    if '/Rig_Large/' in path: return 'KayKit Large'
    if '/fullplate_knight/' in path or preview.get('model') == 'Legacy Knight': return 'Legacy Knight'
    if '/Mixamo/' in path: return 'Mixamo'
    return 'Unknown'


def motion_mode(parent, provenance):
    if provenance.get('source_root_motion') is True:
        return 'Root motion'
    source = str(provenance.get('source_scene', original_path(parent)))
    if source.endswith('/UAL2_Standard_RM.glb'):
        return 'Root motion'
    # UAL_ACTIONS documents the non-root-motion counterpart explicitly.
    if source.endswith('/UAL2_Standard.glb'):
        return 'In place'
    if original_path(parent) in ('art_source/mixamo/crawling_ual.glb', 'assets/animations/ual/mixamo_crawling.tres'):
        return 'In place'  # art_source/mixamo/README.md documents centering hip travel.
    if provenance.get('source_root_motion') is False:
        return 'In place'
    return 'Unknown'


def title_for(name, parent, index):
    if name == 'mixamo_com': return Path(parent['path']).stem
    if not name: return f'Unnamed clip {index + 1}' if type(index) is int else 'Unnamed clip'
    title = re.sub(r'\s+', ' ', re.sub(r'([a-z])([A-Z])', r'\1 \2', name).replace('_', ' ').replace('-', ' ')).strip()
    return title[:1].upper() + title[1:]


def build_animation_catalog(root, art, previous=()):
    root = Path(root).resolve()
    taxonomy = load_taxonomy(root)
    configuration = read_json(root / CLASSIFICATION) or {'version': 1, 'identities': [], 'clip_overrides': []}
    if configuration.get('version') != 1: raise ValueError('Unsupported animation classification version')
    previous_by_id = {entry['id']: entry for entry in previous}
    parents = {entry['id']: entry for entry in art}
    result, seen = [], set()
    fingerprints = Fingerprints(root)
    for parent in art:
        if parent.get('missing'): continue
        preview = parent.get('preview', {})
        descriptors = preview.get('clips', []) if preview.get('kind') == 'model' else []
        descriptors = [clip for clip in descriptors if isinstance(clip, dict)]
        unresolved = not descriptors
        if unresolved:
            descriptors = [dict(id=None, index=None, name=name, duration=None, loop=None) for name in parent.get('clip_names', [])]
        if not descriptors: continue
        counts = Counter(clip.get('name', '') for clip in descriptors)
        fingerprint = preview.get('fingerprint') or fingerprints.combined([parent['path']])
        source_hash = sha256(local_path(root, parent['path']))
        source_path = original_path(parent)
        aliases = {parent['path'], source_path, *parent.get('original_paths', [])}
        provenance_by_alias = source_provenance(root, parent['path'])
        for descriptor in descriptors:
            source_clip = deepcopy(descriptor)
            name = source_clip.get('name', '')
            source_index = source_clip.get('index')
            unique = bool(name) and counts[name] == 1 and not unresolved
            identity = None
            for record in configuration.get('identities', []):
                if (record.get('path') in aliases and record.get('name') == name
                        and record.get('index') == source_index and record.get('fingerprint') == fingerprint):
                    identity = record.get('identity')
                    if not isinstance(identity, str) or not identity.strip(): raise ValueError('Explicit clip identity must be nonempty')
                    break
            stable = clip_id(parent['id'], name)
            if identity:
                identifier = clip_id(parent['id'], '@identity:' + identity)
            elif unique or unresolved and stable in previous_by_id:
                identifier = stable
            else:
                identifier = clip_id(parent['id'], '@unresolved:' + fingerprint + ':' + str(source_index) + ':' + name)
            if identifier in seen: raise ValueError('Duplicate resolved animation clip identity: ' + identifier)
            seen.add(identifier)
            categories, tags = classify(name, source_path, taxonomy)
            for override in configuration.get('clip_overrides', []):
                if override.get('path') in aliases and override.get('name') == name:
                    # An exact-name default override is source-backed curation, not approval.
                    if override.get('source_sha256') and override['source_sha256'] != source_hash:
                        continue
                    categories = override.get('animation_categories', categories)
                    tags = override.get('animation_tags', tags)
            if set(categories) - set(taxonomy['categories']) or set(tags) - set(taxonomy['tags']):
                raise ValueError('Clip override uses an undeclared category or tag')
            source = provenance_by_alias.get(name, provenance_by_alias.get('', {}))
            preview_copy = deepcopy(preview)
            if unresolved:
                preview_copy = unavailable(preview.get('reason', 'Clip metadata is known, but its playback binding is unavailable.'),
                    status=preview.get('status') if preview.get('status') in {'stale', 'unavailable'} else 'unavailable')
            else:
                preview_copy['clips'] = [source_clip]
            entry = {key: deepcopy(parent[key]) for key in ('path', 'url', 'origin', 'role', 'collections', 'modified_at') if key in parent}
            entry.update(id=identifier, title=title_for(name, parent, source_index), kind='Animation clips',
                types=['Animations'], image=False, missing=False, parent_id=parent['id'],
                parent_title=parent.get('title', ''), source_clip=source_clip,
                clip_names=[name] if name else [], clip_status='available' if not unresolved else 'unavailable',
                identity_editable=bool(unique or identity) and not unresolved, identity_key=identity,
                unresolved=unresolved or not (unique or identity), animation_categories=categories, animation_tags=tags,
                source_library=library(str(source.get('source_scene', source_path)).removeprefix('res://')),
                rig=rig_name(parent), motion_mode=motion_mode(parent, source), preview=preview_copy,
                sources=[parent['path']], classification_evidence=dict(kind='clip_name', value=Path(source_path).stem if name == 'mixamo_com' else name))
            entry.update(naming_fields(name, parent, source_clip, configuration.get('clip_overrides', []), source_hash))
            for override in configuration.get('clip_overrides', []):
                if (override.get('path') in aliases and override.get('name') == name
                        and override.get('source_sha256') == source_hash and 'motion_mode' in override):
                    if override['motion_mode'] not in {'Root motion', 'In place', 'Unknown'}:
                        raise ValueError('Unknown documented animation motion mode')
                    entry['motion_mode'] = override['motion_mode']
            if not entry['identity_editable']:
                entry['identity_reason'] = ('The exact playback binding is unavailable.' if unresolved else
                    'Unnamed or duplicate clips need an explicit, fingerprint-pinned identity before per-clip edits.')
            result.append(entry)
    # Vanished clips retain their identity and generated metadata; sparse user
    # annotations remain in tracking.json, never copied into this catalog.
    for identifier, old in previous_by_id.items():
        if identifier in seen: continue
        entry = deepcopy(old)
        parent = parents.get(entry.get('parent_id'))
        entry['missing'] = True
        if not parent or parent.get('missing'):
            reason = 'The original asset is missing.'
        elif parent.get('preview', {}).get('status') != 'ready' and not parent.get('clip_names'):
            reason = 'Current clip metadata is unavailable; the previous identity and notes are retained.'
            entry.update(missing=False, unresolved=True, identity_editable=False)
        else:
            reason = 'This clip is no longer present in the source animation metadata.'
        entry['preview'] = unavailable(reason)
        if 'naming_status' not in entry:
            entry.update(naming_fields(entry.get('source_clip', {}).get('name', ''), parent or entry,
                entry.get('source_clip', {})))
        result.append(entry)
    audit_path = root / 'docs/tracker/animation_audit.json'
    audit = json.loads(audit_path.read_text(encoding='utf-8')) if audit_path.is_file() else None
    apply_duplicate_audit(root, result, audit)
    result.sort(key=lambda entry: (entry.get('parent_id', ''), entry.get('source_clip', {}).get('index') if type(entry.get('source_clip', {}).get('index')) is int else 10**9, entry['id']))
    categories = []
    for label, slug in CATEGORY_SLUGS.items():
        members = [entry for entry in result if label in entry.get('animation_categories', [])]
        categories.append(dict(id='art:category:' + slug, title=label, category_label=label, kind='Animation categories', animation_category=True,
            members=[entry['id'] for entry in members], clip_count=sum(not entry.get('missing') for entry in members),
            missing_count=sum(bool(entry.get('missing')) for entry in members), member_count=len(members),
            types=['Animations'], collections=[], origin='Project files', role='', image=False, missing=False,
            path=TAXONOMY, url='', sources=[TAXONOMY], modified_at=max((entry.get('modified_at', '') for entry in members), default=''),
            clip_names=[], clip_status='not_applicable', animation_categories=[label], animation_tags=[]))
    return result, categories, taxonomy
