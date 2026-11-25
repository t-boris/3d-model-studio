"""Derive invalid packages from the known-good repeated block for Workspace.open."""
from pathlib import Path
import sys
from zipfile import ZipFile, ZIP_DEFLATED

fixtures = Path("Fixtures/Import/Assemblies")
with ZipFile(fixtures / "repeated-block.3mf") as source:
    parts = {name: source.read(name).decode() for name in source.namelist()}

root = "3D/root.model"
child = "3D/parts/block.model"
rels = "3D/_rels/root.model.rels"
cases = [
    ("missing-part", child, None, None),
    ("missing-relationship", rels, 'Target="parts/block.model"', 'Target="unused.model"'),
    ("missing-object", root, 'objectid="2"', 'objectid="31"'),
    ("invalid-index", child, 'v1="0"', 'v1="100"'),
    ("invalid-xml", child, '</resources>', '</unexpected>'),
    ("invalid-transform", root, '60 2 3', '60 2 NaN'),
    ("cyclic", child, 'component objectid="1"', 'component objectid="2"'),
    ("late-missing-object", root, '<item objectid="2"', '<item objectid="31"'),
    ("child-cross-part", child, 'component objectid="1"', 'component objectid="1" prod:path="/3D/root.model"'),
    ("external-start", "_rels/.rels", "Target=", 'TargetMode="External" Target='),
    ("external-path", root, '/3D/parts/block.model', 'https://example.invalid/block.model'),
    ("external-relationship", rels, 'Target=', 'TargetMode="External" Target='),
    ("escape", root, '/3D/parts/block.model', '/%2e%2e/private/block.model'),
    ("unknown-extension", root, 'requiredextensions="prod"', 'requiredextensions="other"'),
]
for case, part, old, new in cases:
    modified = parts.copy()
    if old is None:
        del modified[part]
    else:
        assert old in modified[part]
        modified[part] = modified[part].replace(old, new, 1)
    with ZipFile(Path(sys.argv[1]) / (case + ".3mf"), "w", ZIP_DEFLATED) as archive:
        for name, body in modified.items():
            archive.writestr(name, body)
