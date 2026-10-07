"""Extract the fictional OCR proof before Flutter removes its test container."""

import json
import pathlib
import re
import sys


def collect(platform, log_path, output_path):
    if platform not in ("ios", "android"):
        raise ValueError("Unsupported test platform")
    log = pathlib.Path(log_path).read_text(encoding="utf-8")
    log = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", log)
    marker = "TALLERFLOW_NATIVE_EVIDENCE:"
    records = []
    decoder = json.JSONDecoder()
    for line in log.splitlines():
        if marker in line:
            record, _ = decoder.raw_decode(line.split(marker, 1)[1].lstrip())
            records.append(record)
    if len(records) != 1:
        raise ValueError("Exactly one completed OCR evidence record is required")
    record = records[0]
    expected = 6 if platform == "ios" else 5
    if (
        record.get("platform") != platform
        or record.get("passed") != expected
        or len(record.get("checks", [])) != expected
        or any(
            record.get(flag) is not False
            for flag in (
                "physicalCameraValidated",
                "microphoneUsed",
                "hostedAuthValidated",
            )
        )
    ):
        raise ValueError("Incomplete evidence or incorrect validation scope")
    target = pathlib.Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(f"{platform}: {expected} native OCR assertions recorded; physical use pending")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("Usage: collect_native_ocr_evidence.py PLATFORM LOG OUTPUT")
    collect(*sys.argv[1:])
