"""Rebuilding must preserve the approved retarget and both provenance hashes."""
import contextlib
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_mixamo_crawl
import crawl_retarget as fit


class MixamoCrawlBuildTests(unittest.TestCase):
    def test_fitted_shoulders_preserve_limb_lengths_and_authored_hand_contacts(self):
        _, document, channels = build_mixamo_crawl.read_snapshot()
        nodes = document['nodes']
        ids = {node.get('name'): i for i, node in enumerate(nodes)}
        parents = {child: i for i, node in enumerate(nodes) for child in node.get('children', [])}
        times, rotations = fit.corrected_rotations(document, channels)
        corrected = channels.copy()
        for bone, values in rotations.items():
            corrected[bone, 'rotation'] = (times, values, 'LINEAR')
        original_gap = 0.0
        # Include quarter frames: hand contacts must remain stable between baked
        # keys, not just at the exact samples used by the fitting algorithm.
        for frame in range(217):
            time = 1.8*frame/216
            original = fit.pose_at(nodes, channels, time)
            pose = fit.pose_at(nodes, corrected, time)
            for bone in pose:
                self.assertEqual(pose[bone][0], original[bone][0], 'Never stretch a limb or translate its joint')
                if bone not in rotations:
                    self.assertEqual(pose[bone][1], original[bone][1], 'Unrelated source motion is unchanged')
            for side in ('l', 'r'):
                clavicle, upper, hand = (ids[name+'_'+side] for name in ('clavicle', 'upperarm', 'hand'))
                torso_position, torso_rotation = fit.world_pose(pose, parents, parents[clavicle])
                rest = nodes[clavicle]
                socket_local = fit.add(pose[clavicle][0], fit.rotate(fit.unit(rest['rotation']), pose[upper][0]))
                socket = fit.add(torso_position, fit.rotate(torso_rotation, socket_local))
                actual = fit.world_pose(pose, parents, upper)[0]
                self.assertLess(fit.length(fit.sub(socket, actual)), 1e-5, 'Shoulder socket stays attached to chest')
                before, before_rotation = fit.world_pose(original, parents, hand)
                after, after_rotation = fit.world_pose(pose, parents, hand)
                self.assertLess(fit.length(fit.sub(before, after)), 0.0015, 'Hands retain source ground contacts')
                self.assertGreater(abs(fit.dot(before_rotation, after_rotation)), 0.9999, 'Palms retain their orientation')
                # Demonstrate that the original fixture contains the reported defect.
                source_torso, source_rotation = fit.world_pose(original, parents, parents[clavicle])
                source_socket = fit.add(source_torso, fit.rotate(source_rotation, socket_local))
                original_gap = max(original_gap, fit.length(fit.sub(source_socket, fit.world_pose(original, parents, upper)[0])))
        self.assertGreater(original_gap, 0.15)

    def test_approved_snapshot_rebuild_is_reproducible_without_mutating_sources(self):
        original = build_mixamo_crawl.ORIGINAL.read_bytes()
        snapshot = build_mixamo_crawl.SOURCE.read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'crawl.tres'
            with patch.object(build_mixamo_crawl, 'OUTPUT', output), contextlib.redirect_stdout(io.StringIO()):
                build_mixamo_crawl.build()
            self.assertEqual(output.read_bytes(), build_mixamo_crawl.OUTPUT.read_bytes())
            text = output.read_text()
            self.assertIn(hashlib.sha256(original).hexdigest(), text)
            self.assertIn(hashlib.sha256(snapshot).hexdigest(), text)
        self.assertEqual(original, build_mixamo_crawl.ORIGINAL.read_bytes())
        self.assertEqual(snapshot, build_mixamo_crawl.SOURCE.read_bytes())


if __name__ == '__main__':
    unittest.main()
