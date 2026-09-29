#!/usr/bin/env python3
"""Generated tags describe existing catalog classifications only."""
import copy
import json
from pathlib import Path
import unittest

from dev_book_catalog import apply_dev_metadata


class DevMetadataTests(unittest.TestCase):
    def test_topic_and_subtopic_preserve_evidence(self):
        feature = dict(id='walking', area='Gameplay', category='Gameplay mechanics', topic='Movement',
                       subcategory='Ground movement', title='Walking', summary='Existing description',
                       sources=['docs/MOTION_PIPELINE.md'], status='Implemented', checklist=[])
        original = copy.deepcopy(feature)
        result = apply_dev_metadata([feature])
        self.assertIs(result[0], feature)
        self.assertEqual(feature['dev_tags'], ['Movement', 'Ground movement'])
        self.assertEqual({k: v for k, v in feature.items() if k != 'dev_tags'}, original)

    def test_duplicates_and_chapter_aliases_are_excluded(self):
        features = [dict(area='Systems', topic=' Character architecture ', subcategory='character_architecture'),
                    dict(area='Systems', topic='Game systems', subcategory='Systems'),
                    dict(area='Gameplay', topic='Gameplay mechanics', subcategory='Gameplay'),
                    dict(area='UI', topic='UI', subcategory='UI')]
        apply_dev_metadata(features)
        self.assertEqual(features[0]['dev_tags'], ['Character architecture'])
        self.assertTrue(all(item['dev_tags'] == [] for item in features[1:]))

    def test_no_keyword_inference_or_tracking_mutation(self):
        feature = dict(title='Healing', summary='Possible horse mounting', note='Not approved', dev_tags=['Invented'],
                       attention=['Bug found'], status='Deferred', checklist=[dict(done=False)])
        apply_dev_metadata([feature])
        self.assertEqual(feature['dev_tags'], [])
        self.assertEqual(feature['attention'], ['Bug found'])
        self.assertEqual(feature['status'], 'Deferred')
        self.assertFalse(feature['checklist'][0]['done'])

    def test_missing_fields_safe_and_rebuild_idempotent(self):
        features = [{}, dict(topic=None, subcategory=4), dict(topic='Combat', subcategory='Combat')]
        self.assertIs(apply_dev_metadata(features), features)
        snapshot = copy.deepcopy(features)
        apply_dev_metadata(features)
        self.assertEqual(features, snapshot)
        self.assertEqual(features[-1]['dev_tags'], ['Combat'])

    def test_real_catalog_tags_are_source_backed(self):
        features = json.loads((Path(__file__).resolve().parents[1] / 'docs/tracker/catalog.json').read_text())['features']
        old_ids = [f['id'] for f in features]
        apply_dev_metadata(features)
        self.assertEqual(old_ids, [f['id'] for f in features])
        for feature in features:
            self.assertTrue(set(feature['dev_tags']) <= {feature.get('topic'), feature.get('subcategory')})


if __name__ == '__main__':
    unittest.main()
