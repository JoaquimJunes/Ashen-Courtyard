#!/usr/bin/env python3
"""Exporter integration regressions; uses only disposable fixtures and outputs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get("GODOT_BIN", ROOT / ".artifacts/toolchain/godot"))

SCENE = '''[gd_scene load_steps=5 format=3]
[sub_resource type="BoxMesh" id="Box"]
[sub_resource type="Animation" id="Clip"]
resource_name = "DifferentSourceName"
length = 1.25
tracks/0/type = "%s"
tracks/0/enabled = true
tracks/0/path = NodePath("Cube%s")
tracks/0/interp = 1
tracks/0/keys = %s
[sub_resource type="AnimationLibrary" id="Bank"]
_data = {"ActualRuntimeName": SubResource("Clip")}
[node name="Fixture" type="Node3D"]
[node name="Cube" type="MeshInstance3D" parent="."]
mesh = SubResource("Box")
[node name="AnimationPlayer" type="AnimationPlayer" parent="."]
libraries = {&"": SubResource("Bank")}
'''


@unittest.skipUnless(GODOT.is_file(), "Godot executable not installed")
class ExporterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="preview-export-", dir=ROOT / ".artifacts")
        cls.folder = Path(cls.tmp.name)
        cls.marker = cls.folder / "script-ran.txt"
        (cls.folder / "bad.gd").write_text('extends Node3D\nfunc _init():\n\tFileAccess.open("%s", FileAccess.WRITE).store_string("ran")\n' % cls.marker)
        (cls.folder / "scripted.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://%s" id="1"]\n[node name="Forbidden" type="Node3D"]\nscript = ExtResource("1")\n' % (cls.folder / "bad.gd").relative_to(ROOT))
        (cls.folder / "rigid.tscn").write_text(SCENE % ("position_3d", "", "PackedFloat32Array(0, 1, 0, 0, 0, 0.75, 1, 0.5, 0, 0, 1.25, 1, 1, 0, 0)"))
        (cls.folder / "unsupported.tscn").write_text(SCENE % ("value", ":position", '{"times": PackedFloat32Array(0, 1.25), "transitions": PackedFloat32Array(1, 1), "update": 0, "values": [Vector3(0, 0, 0), Vector3(1, 0, 0)]}'))
        (cls.folder / "static.tscn").write_text(SCENE % ("position_3d", "", "PackedFloat32Array(0, 1, 0.5, 0, 0)"))
        (cls.folder / "method.tscn").write_text(SCENE % ("method", "", '{"times": PackedFloat32Array(0), "transitions": PackedFloat32Array(1), "values": [{"method": &"queue_free", "args": []}]}'))
        (cls.folder / "missing.tscn").write_text((SCENE % ("position_3d", "", "PackedFloat32Array(0, 1, 0, 0, 0, 1.25, 1, 1, 0, 0)")).replace('NodePath("Cube")', 'NodePath("MissingRig/Skeleton3D:missing_bone")'))
        sources = ["assets/animations/ual/anim_ual_native_actions_library_v01.tres", "assets/animations/anim_legacy_knight_roll_forward_v01.tres", "assets/animations/Mixamo/anim_mixamo_crawling_v01.fbx"]
        sources += [str((cls.folder / f).relative_to(ROOT)) for f in ("rigid.tscn", "unsupported.tscn", "scripted.tscn")]
        sources += ["assets/animations/ual/anim_ual_native_locomotion_library_v01.tres", "assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres", "assets/animations/anim_legacy_knight_jog_v01.tres", "assets/animations/anim_legacy_knight_sprint_v01.tres"]
        sources += [str((cls.folder / f).relative_to(ROOT)) for f in ("method.tscn", "missing.tscn")]
        cls.before = {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources}
        cls.jobs = [{"source": path, "output": str(cls.folder / f"{index}.glb")} for index, path in enumerate(sources)]
        cls.jobs.append({"source": sources[0], "output": "res://assets/third_party/quaternius/UAL1_Standard.glb"})
        cls.jobs.append({"source": str((cls.folder / "static.tscn").relative_to(ROOT)), "output": str(cls.folder / "static.glb")})
        cls.protected = ROOT / "assets/third_party/quaternius/UAL1_Standard.glb"
        cls.protected_before = hashlib.sha256(cls.protected.read_bytes()).hexdigest()
        jobs = cls.folder / "jobs.json"
        report = cls.folder / "report.json"
        jobs.write_text(json.dumps({"jobs": cls.jobs}))
        result = subprocess.run([str(GODOT), "--headless", "--log-file", str(cls.folder / "godot.log"), "--path", str(ROOT), "--script", "res://tools/export_art_previews.gd", "--", "--jobs", str(jobs), "--report", str(report)], cwd=ROOT, capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.results = json.loads(report.read_text())["results"]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_corrected_runtime_library_and_root_motion_roundtrip(self):
        result = self.results[0]
        self.assertEqual(result["status"], "ready", result.get("reason"))
        self.assertEqual(result["model"], "UAL mannequin")
        clips = {clip["name"]: clip for clip in result["clips"]}
        self.assertEqual(len(clips), 7)
        self.assertAlmostEqual(clips["climb_up_1m_rm"]["duration"], 2 / 3, places=6)
        self.assertIn("spell_idle", clips)
        self.assertGreater(result["validation"]["samples"], 100)
        self.assertLess(result["validation"]["max_position_error_m"], 0.00001)

    def test_legacy_rig_uses_explicit_export_name_mapping(self):
        result = self.results[1]
        self.assertEqual(result["status"], "ready", result.get("reason"))
        self.assertEqual(result["model"], "Legacy Knight")
        self.assertEqual(result["clips"][0]["name"], "roll_forward", "Renaming an unnamed resource must retain its historical clip identity")
        self.assertIn("tools/art_asset_identities.json", result["dependencies"])
        self.assertLess(result["validation"]["max_position_error_m"], 0.00001)
        self.assertTrue(any(path.startswith(".godot/imported/") for path in result["dependencies"]))

    def test_animation_only_mixamo_fbx_uses_explicit_preview_profile(self):
        result = self.results[2]
        self.assertEqual(result["status"], "ready", result.get("reason"))
        self.assertEqual(result["provenance"]["profile_id"], "mixamo_crawl_v1")
        self.assertEqual(result["provenance"]["status"], "pending_visual_review")
        self.assertEqual(result["provenance"]["source_clips"][0]["name"], "mixamo_com")
        self.assertEqual(result["clips"][0]["name"], "mixamo_com")
        self.assertEqual(result["model"], "UAL mannequin")

    def test_rigid_node_and_exact_runtime_alias(self):
        result = self.results[3]
        self.assertEqual(result["status"], "ready", result.get("reason"))
        self.assertEqual(result["clips"][0]["name"], "ActualRuntimeName")
        self.assertEqual(result["clips"][0]["duration"], 1.25)
        self.assertGreater(result["validation"]["samples"], 0)

    def test_unsupported_tracks_fail_without_publishing(self):
        self.assertEqual(self.results[4]["status"], "unavailable")
        self.assertIn("unsupported track", self.results[4]["reason"])
        self.assertFalse(Path(self.jobs[4]["output"]).exists())

    def test_scripts_are_rejected_before_instantiation(self):
        self.assertEqual(self.results[5]["status"], "unavailable")
        self.assertIn("contains a script", self.results[5]["reason"])
        self.assertFalse(self.marker.exists())

    def test_loop_endpoints_and_time_scaled_keys_roundtrip(self):
        for result in self.results[6:10]:
            self.assertEqual(result["status"], "ready", result.get("reason"))
            self.assertGreater(result["validation"]["samples"], 0)
        self.assertAlmostEqual(self.results[8]["validation"]["reimport_sample_fps"], 60 / self.results[8]["clips"][0]["duration"], places=5)

    def test_method_tracks_and_missing_rig_targets_are_rejected(self):
        self.assertEqual(self.results[10]["status"], "unavailable")
        self.assertIn("unsupported track", self.results[10]["reason"])
        self.assertEqual(self.results[11]["status"], "unavailable")
        self.assertIn("target is missing", self.results[11]["reason"])

    def test_source_output_paths_are_protected(self):
        self.assertEqual(self.results[12]["status"], "unavailable")
        self.assertIn("Original assets are protected", self.results[12]["reason"])
        self.assertEqual(hashlib.sha256(self.protected.read_bytes()).hexdigest(), self.protected_before)

    def test_single_key_pose_preserves_its_declared_hold_duration(self):
        result = self.results[13]
        self.assertEqual(result["status"], "ready", result.get("reason"))
        self.assertEqual(result["clips"][0]["duration"], 1.25)
        self.assertEqual(result["validation"]["max_position_error_m"], 0)

    def test_original_sources_unchanged(self):
        for path, digest in self.before.items():
            self.assertEqual(hashlib.sha256((ROOT / path).read_bytes()).hexdigest(), digest)


if __name__ == "__main__":
    unittest.main()
