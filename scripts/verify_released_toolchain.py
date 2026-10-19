#!/usr/bin/env python3
"""Exercise a published Chiasmus release through the parity skill wrappers."""

import argparse
import csv
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile


SCRIPTS = Path(__file__).resolve().parents[1] / "skills/cross-language-crystal-parity/scripts"


def run(arguments, environment):
    result = subprocess.run(arguments, env=environment, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, arguments))}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def verify(version, offline):
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith(("CHIASMUS_", "PORT_"))}
    environment["CHIASMUS_VERSION"] = version
    if offline:
        environment["CHIASMUS_TOOLCHAIN_OFFLINE"] = "1"
    toolchain = run(["bash", str(SCRIPTS / "install_chiasmus_toolchain.sh")], environment).strip()
    with tempfile.TemporaryDirectory(prefix="crystal-forge-release-") as temporary:
        root = Path(temporary)
        (root / "upstream").mkdir()
        (root / "src").mkdir()
        (root / "plans").mkdir()
        (root / "upstream/Widget.java").write_text("public class Widget { public int size() { return 1; } }\n")
        (root / "src/widget.cr").write_text("class Widget\n  def size : Int32\n    1\n  end\nend\n")
        (root / "plans/parity_rules.yml").write_text(
            "version: 1\nsource_language: java\ntarget_language: crystal\n"
            "source:\n  type_map: {int: int}\ntarget:\n  type_map: {Int32: int}\n")
        environment["PORT_RECONCILE_CACHE_DIR"] = str(root / "cache")
        environment["PORT_RECONCILE_OUT"] = str(root / "reports")
        probe = run(["bash", str(SCRIPTS / "verify_skill_install.sh"), str(root), "java", "tree-sitter"], environment)
        if "PARITY_SKILL_VERIFIED=1" not in probe:
            raise RuntimeError("skill preflight did not verify discovery")
        run(["bash", str(SCRIPTS / "reconcile_parity.sh"), str(root), "upstream", "java", "src"], environment)
        reports = root / "reports"
        maps = (reports / "maps.tsv").read_text()
        def rows(text):
            data = "\n".join(line for line in text.splitlines() if line and not line.startswith("#"))
            return list(csv.DictReader(io.StringIO(data), delimiter="\t"))
        matched = rows(maps)
        expected = {"Widget": "Widget", "Widget.size": "Widget.size"}
        if len(matched) != 2 or {row["source_name"]: row["target_name"] for row in matched
                                 if row["status"] == "matched"} != expected:
            raise RuntimeError(f"release did not map Widget:\n{maps}")
        for name in ("surfaces.tsv", "maps.pl", "source-declarations.jsonl", "target-declarations.jsonl"):
            if not (reports / name).stat().st_size:
                raise RuntimeError(f"empty reconciliation artifact: {name}")
        surfaces = rows((reports / "surfaces.tsv").read_text())
        if (len(surfaces) != 1 or surfaces[0]["status"] != "surface_match"
                or surfaces[0]["source_arity"] != "0" or surfaces[0]["target_arity"] != "0"
                or surfaces[0]["return_match"] != "true"):
            raise RuntimeError(f"incorrect reconciled method surface: {surfaces}")
        print(json.dumps({"version": version, "offline": offline, "toolchain": toolchain,
                          "preflight": "passed", "reconciliation": "passed",
                          "maps": maps, "surfaces": (reports / "surfaces.tsv").read_text()}, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    verify(args.version, args.offline)
