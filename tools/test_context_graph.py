"""Checks for the Godot context indexer; no Godot launch or API required."""
import json
import importlib.util
from pathlib import Path
import tempfile
import unittest

from build_context_graph import Index, digest


class ContextGraphTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.project = self.workspace / "souls"
        self.project.mkdir()

    def write(self, name, text):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def index(self):
        index = Index(self.project, self.workspace)
        index.scan()
        return index

    def test_calls_exclude_strings_comments_and_untyped_receivers(self):
        self.write("actor.gd", 'extends RefCounted\nfunc tick():\n\tstep()\n\t# step()\n\tvar text = "step()"\n\tunknown.step()\nfunc step():\n\tpass\n')
        calls = [e for e in self.index().edges if e["relation"] == "calls"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["source_location"], "L3")

    def test_typed_receiver_and_parameter_shadowing(self):
        self.write("motor.gd", 'extends RefCounted\nfunc step():\n\tpass\n')
        self.write("actor.gd", 'extends RefCounted\nconst Motor = preload("res://motor.gd")\nvar motor: Motor\nfunc tick():\n\tmotor.step()\nfunc other(motor):\n\tmotor.step()\n')
        calls = [e for e in self.index().edges if e["relation"] == "calls"]
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["confidence"], "INFERRED")

    def test_resources_docs_and_combat_token_included(self):
        token = self.write("strike_token.gd", 'extends RefCounted\nfunc claim():\n\tpass\n')
        scene = self.write("player.tscn", '[ext_resource type="Script" path="res://strike_token.gd" id="1"]\n')
        self.write("GUIDE.md", '# Combat\nSee `strike_token.gd` and [scene](player.tscn).\n')
        index = self.index()
        self.assertIn(index.file_id(token), index.nodes)
        self.assertTrue(any(e["source"] == index.file_id(scene) and e["target"] == index.file_id(token) for e in index.edges))
        self.assertEqual(len([e for e in index.edges if e["relation"] == "references"]), 3)

    def test_rebuild_omits_deleted_sources(self):
        path = self.write("old.gd", 'func obsolete():\n\tpass\n')
        old = self.index()
        path.unlink()
        self.write("new.gd", 'func current():\n\tpass\n')
        new = self.index()
        self.assertTrue(old.nodes)
        self.assertFalse(any("old.gd" in n["source_file"] for n in new.nodes.values()))

    def test_generated_clean_project_is_excluded(self):
        live = self.write("actor.gd", 'class_name Actor\nfunc current():\n\tpass\n')
        self.write(".artifacts/ci/source/actor.gd", 'class_name Actor\nfunc obsolete():\n\tpass\n')
        self.write(".artifacts/ci/source/GUIDE.md", '# Generated copy\nOld contract.\n')
        index = self.index()
        self.assertEqual(list(index.texts), [live])
        self.assertEqual(index.classes["Actor"], live)
        self.assertFalse(any(".artifacts" in n["source_file"] for n in index.nodes.values()))

    def test_semantic_evidence_invalidated_on_document_change(self):
        path = self.write("GUIDE.md", '# Motion\nCurrent contract.\n')
        chunk = self.workspace / "fragment.json"
        chunk.write_text(json.dumps({"source_hashes": {"souls/GUIDE.md": digest(path)},
                                     "nodes": [{"id": "motion", "label": "Motion", "file_type": "concept", "source_file": str(path)}], "edges": []}))
        fresh = self.index()
        fresh.semantic([chunk])
        self.assertIn("motion", fresh.nodes)
        path.write_text('# Motion\nChanged contract.\n')
        stale = self.index()
        stale.semantic([chunk])
        self.assertNotIn("motion", stale.nodes)
        self.assertEqual(stale.semantic_stale, ["souls/GUIDE.md"])

    def test_document_alias_merges_and_preserves_relationship_evidence(self):
        path = self.write("GUIDE.md", '# Motion\nMotor owns collisions.\n')
        chunk = self.workspace / "fragment.json"
        chunk.write_text(json.dumps({"source_hashes": {"souls/GUIDE.md": digest(path)},
            "nodes": [{"id": "doc_alias", "label": "GUIDE.md", "file_type": "document", "source_location": "L1", "source_file": str(path)},
                      {"id": "motor_concept", "label": "Motor", "file_type": "concept", "source_file": str(path)}],
            "edges": [{"source": "doc_alias", "target": "motor_concept", "relation": "describes", "confidence": "EXTRACTED", "confidence_score": 1.0, "source_file": str(path), "source_location": "L2"}],
            "hyperedges": [{"nodes": ["doc_alias", "motor_concept"]}]}))
        index = self.index()
        index.semantic([chunk])
        self.assertNotIn("doc_alias", index.nodes)
        edge = next(e for e in index.edges if e["relation"] == "describes")
        self.assertEqual(edge["source"], index.file_id(path))
        self.assertEqual(edge["source_location"], "L2")
        self.assertEqual(index.hyperedges[0]["nodes"][0], index.file_id(path))
        self.assertIn("motor_concept", index.nodes)
        self.assertTrue(any(n.get("kind") == "section" for n in index.nodes.values()))

    def test_native_file_alias_merges_but_symbol_survives(self):
        path = self.write("tool.py", 'def run():\n    pass\n')
        index = self.index()
        index.native({"nodes": [
            {"id": "tool", "label": "tool.py", "source_file": str(path), "source_location": "L1", "file_type": "code"},
            {"id": "tool_run", "label": "run", "source_file": str(path), "source_location": "L1", "file_type": "code"}],
            "edges": [{"source": "tool", "target": "tool_run", "relation": "contains", "source_file": str(path), "source_location": "L1"}]})
        self.assertNotIn("souls_tool", index.nodes)
        self.assertIn("souls_tool_run", index.nodes)
        self.assertEqual(index.edges[-1]["source"], index.file_id(path))
        self.assertEqual(sum(n.get("kind") == "file" for n in index.nodes.values()), 1)

    def test_same_basename_and_slug_collision_remain_distinct(self):
        paths = [self.write(name, 'func run():\n\tpass\n') for name in ("a-b/player.gd", "a_b/player.gd", "other/player.gd")]
        index = self.index()
        self.assertEqual(len({index.file_id(p) for p in paths}), 3)
        self.assertEqual(len(index.nodes), 6)
        self.assertEqual(len({n["label"] for n in index.nodes.values() if n.get("kind") == "file"}), 3)

    def test_wrapper_is_marked_without_merging_implementation(self):
        target = self.write("features/character/player.gd", 'func step():\n\tpass\n')
        wrapper = self.write("scripts/player.gd", 'extends "res://features/character/player.gd"\n## Compatibility path; edit the feature implementation.\n')
        index = self.index()
        index.organize()
        self.assertTrue(index.nodes[index.file_id(wrapper)]["compatibility_wrapper"])
        self.assertFalse(index.nodes[index.file_id(target)]["compatibility_wrapper"])
        self.assertTrue(any(e["relation"] == "compatibility_wrapper_for" and e["target"] == index.file_id(target) for e in index.edges))

    @unittest.skipUnless(importlib.util.find_spec('tree_sitter_javascript'), 'Use the recorded Graphify Python for web syntax checks')
    def test_web_imports_are_literal_syntax_not_comments_strings_or_packages(self):
        sources = {name: self.write('web/' + name, '// source\n') for name in ('model.js', 'browser.js', 'media.js', 'unused.js')}
        page = self.write('web/app.js', '''import {defaults} from './model.js';
export {project} from './browser.js';
const media = import('./media.js');
const m = require('./model.js');
// require('./unused.js');
const example = "import('./unused.js')";
const remote = import('https://example.com/model.js');
const packageImport = require('unused.js');
const computed = import('./' + 'unused.js');
const pattern = /require('./unused.js')/;
''')
        index = self.index()
        edges = [e for e in index.edges if e['source'] == index.file_id(page)]
        self.assertEqual([(e['target'], e['relation'], e['source_location']) for e in edges],
                         [(index.file_id(sources['model.js']), 'imports', 'L1'),
                          (index.file_id(sources['browser.js']), 'reexports', 'L2'),
                          (index.file_id(sources['media.js']), 'imports', 'L3'),
                          (index.file_id(sources['model.js']), 'imports', 'L4')])

    @unittest.skipUnless(importlib.util.find_spec('tree_sitter_javascript'), 'Use the recorded Graphify Python for web syntax checks')
    def test_page_scripts_styles_and_source_links_connect_web_files(self):
        model = self.write('docs/tracker/model.js', '// model\n')
        app = self.write('docs/tracker/app.js', '// app\n')
        browser = self.write('docs/tracker/animation-browser.js', '// clips\n')
        css = self.write('docs/tracker/style.css', 'body {}\n')
        page = self.write('docs/tracker/index.html', '''<!-- <script src="missing.js"></script> -->
<script src="model.js"></script><script src="app.js"></script>
<script src="animation-browser.js"></script>
<link rel="stylesheet" href="style.css?version=1">
<a href="model.js#L1">Model source</a>
''')
        index = self.index()
        edges = [e for e in index.edges if e['source'] == index.file_id(page)]
        self.assertEqual([(e['target'], e['relation'], e['source_location']) for e in edges],
                         [(index.file_id(model), 'loads_script', 'L2'), (index.file_id(app), 'loads_script', 'L2'),
                          (index.file_id(browser), 'loads_script', 'L3'), (index.file_id(css), 'loads_stylesheet', 'L4'),
                          (index.file_id(model), 'references', 'L5')])

    def test_css_literals_exclude_comments_and_unrelated_strings(self):
        theme = self.write('web/theme.css', 'body {}')
        picture = self.write('web/icon.png', 'placeholder')
        unused = self.write('web/unused.png', 'placeholder')
        css = self.write('web/style.css', '''@import "theme.css";
.icon { background: url("icon.png"); }
/* url(unused.png) */
.example { content: "url(unused.png)"; }
''')
        index = self.index()
        edges = [e for e in index.edges if e['source'] == index.file_id(css)]
        self.assertEqual([(e['target'], e['relation'], e['source_location']) for e in edges],
                         [(index.file_id(theme), 'imports_stylesheet', 'L1'), (index.file_id(picture), 'references', 'L2')])
        self.assertNotIn(index.file_id(unused), index.nodes)

    @unittest.skipUnless(importlib.util.find_spec('tree_sitter_javascript'), 'Use the recorded Graphify Python for web syntax checks')
    def test_generated_and_vendor_web_files_never_enter_graph_even_when_referenced(self):
        excluded = [self.write(path, '// generated\n') for path in (
            'docs/tracker/data.js', 'docs/tracker/catalog.json', 'docs/tracker/previews/demo.js',
            'docs/tracker/vendor/three/module.js', 'node_modules/library/index.js')]
        self.write('docs/tracker/app.js', "import './vendor/three/module.js';\nimport './previews/demo.js';\nrequire('./data.js');\n")
        self.write('docs/tracker/index.html', '<script src="data.js"></script><a href="catalog.json">data</a>')
        self.write('GUIDE.md', '# Source\n[Generated catalog](docs/tracker/catalog.json) and `docs/tracker/data.js`.\n')
        index = self.index()
        for path in excluded:
            self.assertNotIn(path, index.texts)
            self.assertNotIn(index.file_id(path), index.nodes)
        self.assertFalse(any('vendor' in n['source_file'] or '/previews/' in n['source_file'] for n in index.nodes.values()))

    @unittest.skipUnless(importlib.util.find_spec('tree_sitter_javascript'), 'Use the recorded Graphify Python for web syntax checks')
    def test_native_js_symbols_survive_without_false_member_dispatch(self):
        path = self.write('app.js', 'const get=()=>1;\nfunction read(){return map.get("x");}\n')
        index = self.index()
        index.native({'nodes': [
            {'id': 'app', 'label': 'app.js', 'source_file': str(path), 'source_location': 'L1', 'file_type': 'code'},
            {'id': 'read', 'label': 'read()', 'source_file': str(path), 'source_location': 'L2', 'file_type': 'code'},
            {'id': 'get', 'label': 'get()', 'source_file': str(path), 'source_location': 'L1', 'file_type': 'code'}],
            'edges': [{'source': 'read', 'target': 'get', 'relation': 'calls', 'source_file': str(path), 'source_location': 'L2'}]})
        self.assertTrue(any(n['label'] == 'read()' for n in index.nodes.values()))
        self.assertFalse(any(e['relation'] == 'calls' for e in index.edges))


if __name__ == "__main__":
    unittest.main()
