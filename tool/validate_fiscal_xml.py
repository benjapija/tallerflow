"""Validate fictional local fixtures against pinned official schemas, offline."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", default="build/fiscal-fixtures")
    parser.add_argument("--output", default="build/fiscal-fixtures/schema-result.json")
    args = parser.parse_args()
    schemas = Path(__file__).resolve().parent / "fixtures/aeat"
    fixtures = Path(args.fixtures).resolve()
    executable = shutil.which("xmllint")
    if not executable:
        raise SystemExit("Install libxml2-utils to validate XML; no online fallback.")
    checks = []
    sources = json.loads((schemas / "sources.json").read_text())
    for item in sources["files"]:
        actual = hashlib.sha256((schemas / item["name"]).read_bytes()).hexdigest()
        assert actual == item["sha256"], item["name"]
        checks.append({"check": "pinned schema " + item["name"], "passed": True})
    env = dict(os.environ, XML_CATALOG_FILES=str(schemas / "catalog.xml"))

    def validate(path, expected, label):
        result = subprocess.run(
            [executable, "--nonet", "--noout", "--schema",
             str(schemas / "SuministroLR.xsd"), str(path)],
            env=env, capture_output=True, text=True, check=False,
        )
        if (result.returncode == 0) != expected:
            raise AssertionError(label + "\n" + result.stderr)
        checks.append({"check": label, "passed": True})

    for name in ["high", "cancellation"]:
        validate(fixtures / (name + ".xml"), True, name + " matches official XSD")
    sf = "{https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd}"
    high = (fixtures / "high.xml").read_text()
    with tempfile.TemporaryDirectory(prefix="tallerflow-fiscal-") as temp:
        path = Path(temp) / "invalid.xml"
        root = ET.fromstring(high)
        record = root.find(".//" + sf + "RegistroAlta")
        record.remove(record.find(sf + "SistemaInformatico"))
        ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
        validate(path, False, "missing system cannot pass XSD")
        path.write_text(high.replace("<sf:Impuesto>01</sf:Impuesto>", "<sf:Impuesto>99</sf:Impuesto>"))
        validate(path, False, "unknown tax code cannot pass XSD")
        path.write_text(high.replace("<sf:ImporteTotal>121.00</sf:ImporteTotal>", "<sf:ImporteTotal>121,00</sf:ImporteTotal>"))
        validate(path, False, "decimal comma cannot pass XSD")
    result = {
        "scope": "Local fictional XML validation against pinned official XSD, not AEAT service acceptance",
        "checks": checks, "passed": len(checks),
        "schemas": sources["files"], "officialServiceCalled": False,
        "fiscalEmissionEnabled": False,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"{len(checks)} offline fiscal XML checks passed; emission remains disabled.")


if __name__ == "__main__":
    main()
