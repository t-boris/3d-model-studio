"""Boundary and malformed-output checks for the PrusaSlicer evidence comparison."""
from pathlib import Path
import runpy

compare = runpy.run_path(str(Path(__file__).resolve().parents[1] / "Scripts/compare-prusaslicer.py"))["compare"]
for axis in range(3):
    for value, accepted in [("9.99", True), ("10.01", True), ("9.9899", False), ("10.0101", False)]:
        rows = ["size_" + key + " = " + (value if i == axis else "10") for i, key in enumerate("xyz")]
        result = compare("\n".join(rows), [10] * 3)
        assert all(ok for ok, _ in result) == accepted

for text in ["", "size_x = 1\nsize_y = 1", "size_x = NaN", "size_x = invalid", "size_x = 1\nsize_x = 2"]:
    try:
        compare(text, [1] * 3)
    except ValueError:
        continue
    raise AssertionError(text)
print("All three axis limits, missing and ambiguous sizes, and invalid numbers passed.")
