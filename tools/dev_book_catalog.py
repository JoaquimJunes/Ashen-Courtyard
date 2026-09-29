"""Source-backed Dev book labels; no invented tasks or completion claims."""
import re
import unicodedata


def _key(value):
    value = unicodedata.normalize('NFKD', value).casefold()
    return re.sub(r'[\s_\-]+', ' ', ''.join(c for c in value if not unicodedata.combining(c))).strip()


CHAPTERS = {_key(label) for label in ('Systems', 'Gameplay', 'UI', 'Game systems', 'Gameplay mechanics')}


def apply_dev_metadata(features):
    """Regenerate only dev_tags from each feature's existing topic/subcategory."""
    for feature in features:
        tags, seen = [], set(CHAPTERS)
        area = feature.get('area')
        if isinstance(area, str):
            seen.add(_key(area))
        for field in ('topic', 'subcategory'):
            value = feature.get(field)
            if not isinstance(value, str):
                continue
            label = ' '.join(value.split())
            key = _key(label)
            if key and key not in seen:
                tags.append(label)
                seen.add(key)
        feature['dev_tags'] = tags
    return features
