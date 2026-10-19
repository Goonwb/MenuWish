"""Check bundled blank OOXML packages without installing an office application."""
from pathlib import Path
from posixpath import dirname, join, normpath
from sys import argv
from urllib.parse import unquote
from xml.etree import ElementTree as ET
from zipfile import ZipFile

templates = Path(argv[1]) / "MenuWish/Resources/Templates"
ns = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
}
main_parts = {
    "docx": ("word/document.xml", "wordprocessingml.document"),
    "xlsx": ("xl/workbook.xml", "spreadsheetml.sheet"),
    "pptx": ("ppt/presentation.xml", "presentationml.presentation"),
}
for extension, (main, content_type) in main_parts.items():
    with ZipFile(templates / f"Blank.{extension}") as archive:
        assert archive.testzip() is None, f"Corrupt {extension} ZIP"
        names = set(archive.namelist())
        assert not any("vbaproject" in name.lower() for name in names), "Unexpected macros"
        parts = {name: ET.fromstring(archive.read(name)) for name in names
                 if name.endswith((".xml", ".rels"))}
        content_types = {node.get("PartName"): node.get("ContentType")
                         for node in parts["[Content_Types].xml"]}
        defaults = {node.get("Extension"): node.get("ContentType")
                    for node in parts["[Content_Types].xml"] if node.get("Extension")}
        assert content_types.get(f"/{main}", defaults.get("xml")) == f"application/vnd.openxmlformats-officedocument.{content_type}.main+xml"
        office_targets = [node.get("Target").lstrip("/") for node in parts["_rels/.rels"]
                          if node.get("Type", "").endswith("/officeDocument")]
        assert office_targets == [main], "Missing main document relationship"
        for name, element in parts.items():
            if not name.endswith(".rels"):
                continue
            base = dirname(dirname(name))
            for relationship in element:
                assert relationship.get("TargetMode") != "External", "Unexpected external link"
                target = unquote(relationship.get("Target"))
                target = target.lstrip("/") if target.startswith("/") else normpath(join(base, target))
                assert target in names, f"Broken relationship: {name} -> {target}"
        if extension == "docx":
            document = parts[main]
            assert not document.findall(".//w:t", ns), "Word template is not blank"
            assert len(document.findall("w:body/w:p", ns)) == 1
        elif extension == "xlsx":
            assert len(parts[main].findall("s:sheets/s:sheet", ns)) == 1
            sheets = [element for name, element in parts.items()
                      if name.startswith("xl/worksheets/") and name.endswith(".xml")]
            assert len(sheets) == 1
            assert not sheets[0].findall(".//s:c", ns), "Excel template has populated cells"
        else:
            assert len(parts[main].findall("p:sldIdLst/p:sldId", ns)) == 1
            size = parts[main].find("p:sldSz", ns)
            assert int(size.get("cx")) * 9 == int(size.get("cy")) * 16
            slide = parts["ppt/slides/slide1.xml"]
            tree = slide.find("p:cSld/p:spTree", ns)
            assert all(node.tag.rsplit("}", 1)[-1] in ("nvGrpSpPr", "grpSpPr") for node in tree), "Slide is not blank"
            assert not slide.findall(".//a:t", ns)
        print(f"PASS: Blank.{extension} package, internal relationships and blank content")
