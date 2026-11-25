#!/usr/bin/env python3
"""Record PrusaSlicer --info for the two REQ-009 acceptance exports."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation

TOLERANCE = Decimal("0.01")
CASES = {"created": (24, 12, 8), "centimeter": (20, 10, 7)}


def compare(output, expected):
    """Require exactly one finite size per axis (the acceptance files each have one build item)."""
    results = []
    for axis, target in zip("xyz", expected):
        values = re.findall(rf"^\s*size_{axis}\s*=\s*(\S+)\s*$", output, re.MULTILINE)
        if len(values) != 1:
            raise ValueError(f"expected exactly one size_{axis}, found {len(values)}")
        try:
            measured = Decimal(values[0])
        except InvalidOperation:
            raise ValueError(f"invalid size_{axis}: {values[0]}") from None
        if not measured.is_finite():
            raise ValueError(f"non-finite size_{axis}: {measured}")
        passed = Decimal(target) - TOLERANCE <= measured <= Decimal(target) + TOLERANCE
        results.append((passed, f"{axis.upper()} measured {measured} mm, expected {target} mm"))
    return results


def run(executable, args, log):
    process = subprocess.run([executable, *args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env={**os.environ, "LC_ALL": "C"})
    log.write_bytes(process.stdout)
    if process.returncode:
        raise ValueError(f"slicer exited {process.returncode}, see {log.name}")
    return process.stdout.decode("utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", help="PrusaSlicer CLI path or command")
    parser.add_argument("created", type=Path, help="edited new block, 24 × 12 × 8 mm")
    parser.add_argument("centimeter", type=Path, help="edited centimeter import, 20 × 10 × 7 mm")
    parser.add_argument("evidence", type=Path, help="new directory for the report and raw CLI output")
    args = parser.parse_args()
    args.evidence.mkdir(parents=True)
    report = []
    success = True
    # The 2.9 CLI prints its version in --help and rejects --version.
    try:
        help_text = run(args.executable, ["--help"], args.evidence / "help.txt")
        version = next((line for line in help_text.splitlines() if re.match(r"^PrusaSlicer[- ]\d", line)), None)
        if not version:
            raise ValueError("PrusaSlicer version missing from --help")
        report.append(version)
    except (OSError, ValueError) as error:
        report.append(f"Version check failed: {error}")
        success = False
    report.append("Tolerance ±0.01 mm inclusive")
    for name, expected in CASES.items():
        path = getattr(args, name).resolve()
        report.append(f"\n{name} ({path.name}), expected X/Y/Z {expected} mm")
        try:
            report.append(f"SHA-256 {hashlib.sha256(path.read_bytes()).hexdigest()}")
            raw = run(args.executable, ["--info", str(path)], args.evidence / f"{name}-info.txt")
            for passed, detail in compare(raw, expected):
                report.append(f"{'PASS' if passed else 'FAIL'} {detail}")
                success = success and passed
        except (OSError, ValueError) as error:
            report.append(f"FAIL {error}")
            success = False
        report.append("GUI opening and rescaling observation: pending")
    summary = "\n".join(report) + "\n"
    (args.evidence / "comparison.txt").write_text(summary, encoding="utf-8")
    print(summary, end="")
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
