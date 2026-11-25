"""Inspect the actual OPC members independently of the Swift reader."""
from pathlib import Path
import sys
from xml.etree import ElementTree as ET
from zipfile import ZipFile

core = "{http://schemas.microsoft.com/3dmanufacturing/core/2015/02}"
relationships = "{http://schemas.openxmlformats.org/package/2006/relationships}"
types = "{http://schemas.openxmlformats.org/package/2006/content-types}"
for path in sorted(Path(sys.argv[1]).glob("*.3mf")):
    with ZipFile(path) as package:
        assert package.testzip() is None
        assert sorted(package.namelist()) == ["3D/3dmodel.model", "[Content_Types].xml", "_rels/.rels"]
        rel, = ET.fromstring(package.read("_rels/.rels")).findall(relationships + "Relationship")
        assert rel.attrib["Type"] == "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
        assert rel.attrib["Target"] == "/3D/3dmodel.model"
        mime = {e.attrib["Extension"]: e.attrib["ContentType"]
                for e in ET.fromstring(package.read("[Content_Types].xml")).findall(types + "Default")}
        assert mime["model"] == "application/vnd.ms-package.3dmanufacturing-3dmodel+xml"
        assert mime["rels"] == "application/vnd.openxmlformats-package.relationships+xml"
        xml = package.read("3D/3dmodel.model")
        model = ET.fromstring(xml)
        assert b"production/" not in xml and "requiredextensions" not in model.attrib
        assert model.tag == core + "model" and model.attrib["unit"] == "millimeter"
        assert all(e.tag.startswith(core) for e in model.iter())
        # Core resources can refer only to previously defined resources.
        ids = set()
        for obj in model.findall(f"{core}resources/{core}object"):
            assert all(c.attrib["objectid"] in ids for c in obj.iter(core + "component"))
            assert obj.attrib["id"] not in ids
            ids.add(obj.attrib["id"])
        assert all(item.attrib["objectid"] in ids for item in model.iter(core + "item"))
    print(f"{path.name}: Core-only package relationships, units and resource order passed.")
