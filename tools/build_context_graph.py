#!/usr/bin/env python3
"""Rebuild the Souls development graph, including Godot formats Graphify skips.

Run with Graphify's Python (see ../GRAPHIFY_GUIDE.md). No network/API calls.
This is a conservative lexical index, not a complete GDScript type checker.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parent
OUTPUT = WORKSPACE / "graphify-out"
EXTENSIONS = {".gd", ".tscn", ".tres", ".gdshader", ".godot", ".py", ".md", ".js", ".cjs", ".html", ".css"}
SKIP = {".git", ".godot", ".artifacts", "graphify-out", "__pycache__", "vendor", "node_modules"}
GENERATED_WEB_FILES = {"docs/tracker/data.js", "docs/tracker/catalog.json"}
FUNCTION = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\((.*?)\)")
STRINGS_COMMENTS = re.compile(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|#[^\n]*')
CSS_REFERENCES = re.compile(r'''/\*[\s\S]*?\*/|(?P<import>@import\s+(?P<quote>["'])(?P<file>[^"'\\]+)(?P=quote))|(?P<url>url\(\s*(?:"(?P<double>[^"\\]+)"|'(?P<single>[^'\\]+)'|(?P<bare>[^\s)'"\\]+))\s*\))|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''', re.I | re.X)


def normalized(value):
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def masked(text):
    """Keep positions/newlines while removing strings/comments from call scanning."""
    return STRINGS_COMMENTS.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), text)


class Index:
    def __init__(self, project=PROJECT, workspace=WORKSPACE):
        self.project, self.workspace = project.resolve(), workspace.resolve()
        self.nodes, self.edges, self.texts, self.functions = {}, [], {}, {}
        self.classes, self.aliases, self.members, self.bases = {}, {}, {}, {}
        self.semantic_stale, self.hyperedges = [], []
        self.merged_file_ids = {}

    def relative(self, path):
        return str(path.resolve().relative_to(self.workspace))

    def file_id(self, path):
        rel = self.relative(path)
        return normalized(rel) + "_" + hashlib.sha256(rel.encode()).hexdigest()[:12] + "_file"

    def file_node(self, path):
        path = path.resolve()
        key = self.file_id(path)
        if key not in self.nodes:
            rel = self.relative(path)
            self.nodes[key] = dict(id=key, label=str(path.relative_to(self.project)), file_type="document" if path.suffix == ".md" else "code",
                                   source_file=rel, source_location="L1", kind="file", path=rel)
        return key

    def merge_file(self, node, path):
        key = self.file_node(path)
        canonical = self.nodes[key]
        self.merged_file_ids[node["id"]] = key
        canonical.setdefault("aliases", []).append(node.get("label", path.name))
        canonical.setdefault("extraction_sources", []).append({k: v for k, v in node.items() if k != "id"})
        return key

    def node(self, path, symbol, line, kind, description=""):
        key = self.file_id(path).removesuffix("_file") + "_" + kind + "_" + normalized(symbol)
        self.nodes[key] = dict(id=key, label=symbol, file_type="document" if kind == "section" else "code",
                               source_file=self.relative(path), source_location=f"L{line}", kind=kind,
                               description=description)
        self.edge(self.file_node(path), key, "contains", path, line)
        return key

    def edge(self, source, target, relation, path, line, inferred=False):
        self.edges.append(dict(source=source, target=target, relation=relation,
                               confidence="INFERRED" if inferred else "EXTRACTED",
                               confidence_score=0.95 if inferred else 1.0,
                               source_file=self.relative(path), source_location=f"L{line}", weight=1.0))

    def resource(self, resource):
        path = (self.project / resource.removeprefix("res://")).resolve()
        return path if not self.excluded(path) and path.is_file() else None

    def excluded(self, path):
        path = path.resolve()
        if not path.is_relative_to(self.project):
            return True
        relative = path.relative_to(self.project)
        return (any(part in SKIP for part in relative.parts) or relative.as_posix() in GENERATED_WEB_FILES
                or relative.parts[:3] == ("docs", "tracker", "previews"))

    def web_reference(self, path, value, relation, line, *, module=False):
        """Resolve explicit project-local links, never packages, URLs or generated files."""
        if not value or value.startswith(('#', '//')) or '\\' in value:
            return
        parsed = urlsplit(value)
        if parsed.scheme or parsed.netloc or not parsed.path:
            return
        if module and not value.startswith(('./', '../', '/')):
            return
        decoded = unquote(parsed.path)
        target = (self.project / decoded.lstrip('/') if decoded.startswith('/') else path.parent / decoded).resolve()
        candidates = [target]
        if module and not target.suffix:
            candidates += [Path(str(target) + suffix) for suffix in ('.js', '.cjs', '.json')]
            candidates += [target / name for name in ('index.js', 'index.cjs')]
        for target in candidates:
            if not self.excluded(target) and target.is_file():
                self.edge(self.file_node(path), self.file_node(target), relation, path, line)
                return

    def javascript_references(self, path):
        """Syntax-backed literal imports/requires; comments and ordinary strings do not count."""
        import tree_sitter_javascript
        from tree_sitter import Language, Parser
        source = self.texts[path].encode('utf-8')
        root = Parser(Language(tree_sitter_javascript.language())).parse(source).root_node
        pending = [root]
        while pending:
            node = pending.pop()
            pending.extend(reversed(node.named_children))
            literal = None
            relation = 'imports'
            if node.type in ('import_statement', 'export_statement'):
                literal = node.child_by_field_name('source')
                relation = 'reexports' if node.type == 'export_statement' else 'imports'
            elif node.type == 'call_expression':
                function, arguments = node.child_by_field_name('function'), node.child_by_field_name('arguments')
                if function and source[function.start_byte:function.end_byte] in (b'require', b'import') and arguments and len(arguments.named_children) == 1:
                    literal = arguments.named_children[0]
            if literal and literal.type == 'string':
                value = source[literal.start_byte + 1:literal.end_byte - 1].decode('utf-8')
                self.web_reference(path, value, relation, node.start_point.row + 1, module=True)

    def html_references(self, path):
        index = self

        class Links(HTMLParser):
            def handle_starttag(self, tag, attributes):
                attributes = dict(attributes)
                line = self.getpos()[0]
                if tag == 'script':
                    index.web_reference(path, attributes.get('src'), 'loads_script', line)
                elif tag == 'link':
                    relation = 'loads_stylesheet' if 'stylesheet' in (attributes.get('rel') or '').split() else 'references'
                    index.web_reference(path, attributes.get('href'), relation, line)
                elif tag == 'a':
                    index.web_reference(path, attributes.get('href'), 'references', line)
                elif tag in ('img', 'iframe', 'video', 'audio', 'source'):
                    index.web_reference(path, attributes.get('src'), 'references', line)

        Links().feed(self.texts[path])

    def css_references(self, path):
        for match in CSS_REFERENCES.finditer(self.texts[path]):
            value = match['file'] or match['double'] or match['single'] or match['bare']
            if value:
                relation = 'imports_stylesheet' if match['import'] else 'references'
                self.web_reference(path, value, relation, self.texts[path].count('\n', 0, match.start()) + 1)

    def scan(self):
        files = sorted(p for p in self.project.rglob("*") if p.is_file() and p.suffix in EXTENSIONS
                       and not self.excluded(p))
        for path in files:
            self.file_node(path)
            self.texts[path] = path.read_text(encoding="utf-8")
            if path.suffix != ".gd":
                continue
            funcs, aliases, members = {}, {}, {}
            for line, raw in enumerate(self.texts[path].splitlines(), 1):
                if match := re.match(r"^class_name\s+(\w+)", raw):
                    self.classes[match[1]] = path
                    self.nodes[self.file_id(path)]["class_name"] = match[1]
                if match := re.match(r"^extends\s+([\w]+)", raw):
                    self.bases[path] = match[1]
                if match := FUNCTION.match(raw):
                    name, params = match.groups()
                    funcs[name] = (self.node(path, f"{path.stem}.{name}", line, "function", raw), line, params)
                if match := re.match(r"^signal\s+(\w+)", raw):
                    self.node(path, f"{path.stem}.{match[1]}", line, "signal", raw)
                if match := re.match(r'^(?:const|var)\s+(\w+)\s*(?::[^=]+)?\s*(?::=|=)\s*preload\(["\'](res://[^"\']+)', raw):
                    if target := self.resource(match[2]):
                        aliases[match[1]] = target
                if match := re.match(r"^(?:@export\s+)?var\s+(\w+)\s*:\s*(\w+)", raw):
                    members[match[1]] = match[2]
            self.functions[path], self.aliases[path], self.members[path] = funcs, aliases, members
        for path in files:
            self.references(path)
            if path.suffix == ".gd":
                self.gd_calls(path)
            elif path.suffix == ".md":
                self.document(path)
            elif path.suffix in ('.js', '.cjs'):
                self.javascript_references(path)
            elif path.suffix == '.html':
                self.html_references(path)
            elif path.suffix == '.css':
                self.css_references(path)
        return files

    def references(self, path):
        """Explicit resource dependencies (including scenes/resources and autoloads)."""
        text = self.texts[path]
        for line, raw in enumerate(text.splitlines(), 1):
            if raw.lstrip().startswith(("#", ";")):
                continue
            for match in re.finditer(r'res://([^"\'\s)]+)', raw):
                if target := self.resource(match[0]):
                    self.edge(self.file_node(path), self.file_node(target), "references", path, line)
        if path in self.bases and (base := self.classes.get(self.bases[path])):
            self.edge(self.file_node(path), self.file_node(base), "inherits", path, 1)

    def resolve_function(self, path, name, visited=None):
        visited = set() if visited is None else visited
        if path in visited:
            return None
        visited.add(path)
        if name in self.functions.get(path, {}):
            return self.functions[path][name][0]
        base = self.classes.get(self.bases.get(path))
        return self.resolve_function(base, name, visited) if base else None

    def gd_calls(self, path):
        lines = masked(self.texts[path]).splitlines()
        funcs = list(self.functions[path].items())
        aliases = self.aliases[path]
        types = {**self.classes, **aliases}
        for index, (name, (caller, start, params)) in enumerate(funcs):
            stop = funcs[index + 1][1][1] - 1 if index + 1 < len(funcs) else len(lines)
            members = {key: types[value] for key, value in self.members[path].items() if value in types}
            # Typed parameters shadow members; unresolved types must not reuse a member.
            for parameter in params.split(","):
                match = re.match(r"\s*(\w+)(?:\s*:\s*(\w+))?", parameter)
                if match:
                    members.pop(match[1], None)
                    if match[2] in types:
                        members[match[1]] = types[match[2]]
            for offset in range(start - 1, stop):
                raw = lines[offset]
                if offset == start - 1:
                    tail = raw[raw.find(")") + 1:]
                    raw = tail.split(":", 1)[1] if ":" in tail else ""
                if match := re.search(r"\bvar\s+(\w+)(?:\s*:\s*(\w+))?", raw):
                    members.pop(match[1], None)
                    if match[2] in types:
                        members[match[1]] = types[match[2]]
                for match in re.finditer(r"(?<![\w.])(?:(\w+)\.)?(\w+)\s*\(", raw):
                    receiver, method = match.groups()
                    target_path = path if receiver in (None, "self") else members.get(receiver, aliases.get(receiver, self.classes.get(receiver)))
                    if target_path and (target := self.resolve_function(target_path, method)):
                        self.edge(caller, target, "calls", path, offset + 1, inferred=receiver not in (None, "self"))

    def document(self, path):
        """Index every heading and its excerpt; link only explicit local citations."""
        lines = self.texts[path].splitlines()
        sections = [(i, line.lstrip("# ")) for i, line in enumerate(lines) if re.match(r"^#{1,6} ", line)]
        for index, (start, title) in enumerate(sections):
            stop = sections[index + 1][0] if index + 1 < len(sections) else len(lines)
            key = self.node(path, f"{title} [L{start + 1}]", start + 1, "section", "\n".join(lines[start:stop])[:1800])
            for offset in range(start, stop):
                raw = lines[offset]
                refs = re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", raw) + re.findall(r"`([^`]+\.(?:gd|tscn|tres|md|py|js|cjs|html|css))`", raw)
                for ref in refs:
                    if "://" in ref and not ref.startswith("res://"):
                        continue
                    candidates = [self.project / ref[6:]] if ref.startswith("res://") else [path.parent / ref, self.project / ref]
                    for target in candidates:
                        target = target.resolve()
                        if not self.excluded(target) and target.is_file():
                            self.edge(key, self.file_node(target), "references", path, offset + 1)
                            break

    def semantic(self, chunks):
        """Only load cached semantic evidence when its source document is unchanged."""
        for chunk in chunks:
            data = json.loads(chunk.read_text())
            hashes = data.get("source_hashes", {})
            valid_sources = {src for src, sha in hashes.items() if (self.workspace / src).is_file() and digest(self.workspace / src) == sha}
            self.semantic_stale.extend(src for src in hashes if src not in valid_sources)
            included = set()
            remap = {}
            for node in data["nodes"]:
                src = str(node.get("source_file") or "")
                path = Path(src) if Path(src).is_absolute() else self.workspace / src
                if self.excluded(path) or not path.is_file():
                    continue
                rel = self.relative(path)
                if path.suffix == ".md" and rel not in valid_sources:
                    continue
                # Code references are canonical file nodes; semantic facts live in docs.
                if node.get("file_type") == "code" or (node.get("file_type") == "document" and node.get("source_location") == "L1"):
                    remap[node["id"]] = self.merge_file(node, path)
                    continue
                node = {**node, "source_file": rel, "kind": "semantic_concept"}
                self.nodes[node["id"]] = node
                included.add(node["id"])
                self.edge(node["id"], self.file_node(path), "documented_in", path, 1)
            for edge in data["edges"]:
                src = str(edge.get("source_file") or "")
                path = Path(src) if Path(src).is_absolute() else self.workspace / src
                if not path.is_relative_to(self.project) or self.relative(path) not in valid_sources:
                    continue
                source = remap.get(edge["source"], edge["source"])
                target = remap.get(edge["target"], edge["target"])
                if source in self.nodes and target in self.nodes:
                    self.edges.append({**edge, "source": source, "target": target, "source_file": self.relative(path)})
            for hyperedge in data.get("hyperedges", []):
                members = list(dict.fromkeys(remap.get(n, n) for n in hyperedge.get("nodes", [])))
                if all(n in self.nodes for n in members):
                    self.hyperedges.append({**hyperedge, "nodes": members})

    def native(self, ast):
        remap = {}
        for original in ast["nodes"]:
            node = dict(original)
            path = Path(node.get("source_file") or "")
            if not path.is_absolute():
                path = self.project / path
            if not path.is_file() or self.excluded(path):
                continue
            node["source_file"] = self.relative(path)
            if node.get("label") == path.name and node.get("source_location") == "L1":
                remap[original["id"]] = self.merge_file(node, path)
            else:
                node["id"] = normalized(self.project.name) + "_" + original["id"]
                node.setdefault("kind", "rationale" if node.get("file_type") == "rationale" else "symbol")
                remap[original["id"]] = node["id"]
                self.nodes[node["id"]] = node
                self.edge(self.file_node(path), node["id"], "contains", path, 1)
        for original in ast["edges"]:
            source_path = Path(original.get('source_file') or '')
            # Native JS dispatch currently conflates obj.get() with a local get().
            # Keep its symbols, but only publish explicit containment and our
            # syntax-backed module links until receiver resolution is reliable.
            if source_path.suffix in ('.js', '.cjs') and original.get('relation') != 'contains':
                continue
            if original["source"] not in remap or original["target"] not in remap:
                continue
            edge = {**original, "source": remap[original["source"]], "target": remap[original["target"]]}
            path = Path(edge.get("source_file") or "")
            if not path.is_absolute():
                path = self.project / path
            edge["source_file"] = self.relative(path)
            self.edges.append(edge)

    def organize(self):
        """Add stable folder-based navigation, independent of statistical clusters."""
        files = {n["source_file"]: n for n in self.nodes.values() if n.get("kind") == "file"}
        for src, file in files.items():
            path = self.workspace / src
            parts = path.relative_to(self.project).parts
            subsystem = (parts[1].title() if parts[0] == "features" and len(parts) > 1 else
                         {"tests": "Tests", "tools": "Tools", "docs": "Documentation", "scripts": "World", "scenes": "World", "assets": "Assets", "data": "Configuration"}.get(parts[0], "Project"))
            if path.suffix == ".md":
                subsystem = "Documentation"
            if subsystem == "Ui":
                subsystem = "UI"
            category = ("documentation" if path.suffix == ".md" else "test" if parts[0] == "tests" else
                        "asset" if path.suffix not in EXTENSIONS else "code")
            text = self.texts.get(path, "")
            wrapper = "Compatibility path; edit the feature implementation." in text
            scene_wrapper = path.suffix == ".tscn" and parts[0] == "scenes" and bool(re.search(r'path="res://features/[^\"]+\.tscn"', text)) and len(text.splitlines()) <= 5
            file.update(subsystem=subsystem, category=category, indexed=path in self.texts,
                        compatibility_wrapper=wrapper or scene_wrapper)
            if wrapper or scene_wrapper:
                for edge in self.edges:
                    if edge["source"] == file["id"] and edge["relation"] == "references":
                        edge["relation"] = "compatibility_wrapper_for"
        for node in self.nodes.values():
            file = files[node["source_file"]]
            node["subsystem"] = file["subsystem"]
            node["category"] = file["category"]
            node["file_id"] = file["id"]
            # Status is copied from explicit semantic annotations, never guessed from code.
            node["status"] = node.get("status", "unspecified")
        assert len(files) == sum(n.get("kind") == "file" for n in self.nodes.values())


def build():
    import networkx as nx
    from graphify.extract import extract
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections, suggest_questions
    from graphify.export import to_json
    from graphify.report import generate

    index = Index()
    files = index.scan()
    OUTPUT.mkdir(exist_ok=True)
    # Native AST supplies Python relationships and JavaScript/CommonJS symbols.
    ast = extract([p for p in files if p.suffix in (".py", ".js", ".cjs")], cache_root=PROJECT)
    index.native(ast)
    index.semantic(sorted(OUTPUT.glob("souls-docs-*.json")))
    index.organize()
    graph = nx.DiGraph()
    for key, attrs in index.nodes.items():
        graph.add_node(key, **{k: v for k, v in attrs.items() if k != "id"})
    graph.graph["hyperedges"] = index.hyperedges
    # Multiple observations of a pair are retained as evidence, not silently lost.
    priority = {"calls": 6, "inherits": 5, "references": 3, "contains": 1}
    for edge in index.edges:
        source, target = edge["source"], edge["target"]
        assert source in graph and target in graph, edge
        evidence = {k: v for k, v in edge.items() if k not in ("source", "target")}
        if graph.has_edge(source, target):
            stored = graph[source][target]
            if evidence not in stored["evidence"]:
                stored["evidence"].append(evidence)
            stored["relations"] = sorted(set(stored["relations"] + [edge["relation"]]))
            if priority.get(edge["relation"], 2) > priority.get(stored["relation"], 2):
                stored.update(evidence)
        else:
            graph.add_edge(source, target, **evidence, evidence=[evidence], relations=[edge["relation"]])
    communities = cluster(graph.to_undirected())
    cohesion = score_all(graph.to_undirected(), communities)
    labels = {}
    for cid, members in communities.items():
        areas = Counter()
        for nid in members:
            parts = Path(graph.nodes[nid]["source_file"]).parts
            area = parts[2] if len(parts) > 2 and parts[1] == "features" else (parts[1] if len(parts) > 1 else "project")
            areas[area] += 1
        labels[cid] = " / ".join(area.replace("_", " ").title() for area, _ in areas.most_common(2))
    gods = god_nodes(graph)
    surprises = surprising_connections(graph, communities)
    questions = suggest_questions(graph, communities, labels)
    detection = {"total_files": len(files), "total_words": sum(len(index.texts[p].split()) for p in files),
                 "files": {"code": [index.relative(p) for p in files if p.suffix != ".md"],
                           "document": [index.relative(p) for p in files if p.suffix == ".md"]}}
    report = generate(graph, communities, cohesion, labels, gods, surprises, detection,
                      {"input": 0, "output": 0}, str(PROJECT), suggested_questions=questions)
    report = report.replace("Token cost: 0 input · 0 output", "Token cost: structural extraction 0; assistant semantic extraction unavailable")
    audit = {"source_root": str(PROJECT), "path_base": str(WORKSPACE), "files": len(files),
             "extensions": dict(Counter(p.suffix for p in files)), "nodes": len(graph),
             "edges": graph.number_of_edges(), "observations": len(index.edges), "dangling_edges": 0,
             "canonical_files": sum(n.get("kind") == "file" for n in index.nodes.values()),
             "merged_file_aliases": len(index.merged_file_ids), "duplicate_file_paths": 0,
             "subsystems": sorted({n["subsystem"] for n in index.nodes.values()}),
             "semantic_stale_sources": sorted(set(index.semantic_stale)),
             "external_api_calls": 0, "semantic_session_tokens": None,
             "limitations": ["GDScript is indexed lexically; dynamic dispatch, scene-node bindings, and untyped receivers are not fully resolved.",
                            "Typed-receiver calls are INFERRED, not proof of runtime behavior.",
                            "JavaScript/CommonJS symbols and literal local imports/reexports/requires are indexed. Dynamic paths, browser-global dispatch and JavaScript call targets are intentionally unresolved.",
                            "HTML script/stylesheet/source links and CSS literal imports/URLs have path edges; inline scripts and escaped/computed URLs are not analyzed. Vendor dependencies, node_modules and generated tracker data/catalog/previews are excluded, including reference-only nodes.",
                            "Images, binary models, generated validation JSON/logs, and import caches are excluded; referenced assets have path nodes only.",
                            "Semantic summaries are assistant-authored; token usage is unavailable. Stale summaries are omitted until refreshed."]}
    report += "\n\n## Souls index coverage and limitations\n\n" + "\n".join("- " + s for s in audit["limitations"])
    report += "\n\nExternal API calls: 0. Local structural extraction token cost: 0. Assistant semantic extraction token usage: unavailable (not zero).\n"
    report += f"\nSource files: {len(files)}. Directed edges: {graph.number_of_edges()}. Dangling edges: 0.\n"
    if index.semantic_stale:
        report += "\nStale semantic summaries omitted: " + ", ".join(sorted(set(index.semantic_stale))) + "\n"
    with tempfile.TemporaryDirectory(prefix="souls-graph-") as tmp:
        stage = Path(tmp)
        to_json(graph, communities, str(stage / "graph.json"), community_labels=labels)
        (stage / "GRAPH_REPORT.md").write_text(report)
        (stage / ".graphify_labels.json").write_text(json.dumps(labels))
        analysis = {"communities": communities, "cohesion": cohesion, "gods": gods, "surprises": surprises}
        (stage / ".graphify_analysis.json").write_text(json.dumps(analysis))
        (stage / ".graphify_detect.json").write_text(json.dumps(detection))
        (stage / "coverage.json").write_text(json.dumps(audit, indent=2))
        template_path = Path(__file__).with_name("context_graph_view.html")
        (stage / "source_manifest.json").write_text(json.dumps({index.relative(p): digest(p) for p in [*files, template_path]}, indent=2))
        if len(graph) > 5000:
            print("Warning: >5,000 nodes; Graphify will aggregate the HTML visualization.")
        subprocess.run([sys.executable, "-m", "graphify", "export", "html", "--graph", str(stage / "graph.json")], check=True, cwd=stage)
        (stage / "graph.html").rename(stage / "graph-detail.html")
        template = template_path.read_text()
        payload = (stage / "graph.json").read_text().replace("<", "\\u003c")
        (stage / "graph.html").write_text(template.replace("__GRAPH_DATA__", payload))
        # Keep one previous set of generated outputs recoverable.
        backup = OUTPUT / "previous-build"
        backup.mkdir(exist_ok=True)
        for name in ("graph.json", "graph.html", "graph-detail.html", "GRAPH_REPORT.md", "coverage.json", "source_manifest.json", ".graphify_labels.json", ".graphify_analysis.json", ".graphify_detect.json"):
            if (OUTPUT / name).exists():
                shutil.copy2(OUTPUT / name, backup / name)
            shutil.copy2(stage / name, OUTPUT / name)
    (OUTPUT / ".graphify_python").write_text(sys.executable)
    (OUTPUT / ".graphify_root").write_text(str(PROJECT))
    print(json.dumps(audit, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    build()
