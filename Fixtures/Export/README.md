# Core 3MF acceptance

These two files came from the workspace export command exercised by the Swift interpreter. Regenerate them or use the checked-in copies for the reference slicer.

| Acceptance file | Edit to reproduce | Expected X × Y × Z | Expected world bounds |
| --- | --- | --- | --- |
| [created.3mf](created.3mf) | Choose **New Block**. Use **Set Once** to set width to 24 mm, depth to 12 mm and height to 8 mm. Export Core 3MF. | 24 × 12 × 8 mm | (0, 0, 0) to (24, 12, 8) mm |
| [centimeter.3mf](centimeter.3mf) | Open the [centimeter Core import](../Import/block.3mf). Set height to 7 mm and export. The source build translates along X and its component rotates about Z. | 20 × 10 × 7 mm | (0, 0, 0) to (20, 10, 7) mm |

## Repeat the checks

From the repository root, choose fresh output and evidence directories. The export suite writes the test files using the app’s workspace, save and export implementations. It also checks failure, repair and reopening.

```sh
Tests/run-export-checks.sh /tmp/studio-exports
Scripts/compare-prusaslicer.py "/Applications/PrusaSlicer.app/Contents/MacOS/PrusaSlicer" \
    /tmp/studio-exports/created.3mf /tmp/studio-exports/centimeter.3mf /tmp/studio-slicer-evidence
```

The comparison obtains the slicer version from its help banner, captures both raw `--info` outputs, and records file hashes, expected values and measured spans. It exits unsuccessfully for a slicer error, missing or ambiguous size, or any axis outside the inclusive ±0.01 mm tolerance.

PrusaSlicer 2.9.7 on macOS reported all six expected spans and both meshes as manifold. Its minimum and maximum coordinates were centered on each object. The placement checks below use the exported build and component transforms. [Comparison and file hashes](Evidence/comparison.txt) · [Created model CLI output](Evidence/created-info.txt) · [Centimeter import CLI output](Evidence/centimeter-info.txt)

## Assembly placement evidence

The export suite extrudes the top of the second occurrence by 2 mm. For each Bambu Studio, OrcaSlicer and repeated-block import, it checks the ordered component tree, build items, local bases and translations in millimeters. It checks the three world-space corners of every triangle in winding order, both directly after editing and after saving, removing the source copy, and reopening. An independent ZIP/XML check verifies that each exported file has one Core model part, internal references and an explicit millimeter unit.

| Source | Exported occurrence bounds in build order, min → max (mm) |
| --- | --- |
| Bambu Studio | (90.00001, 100.99999, 0) → (110.00001, 110.99999, 5) <br> (90, 89.00003, 0) → (110, 99.00003, 7) |
| OrcaSlicer | (90, 101, 0) → (110, 111, 5) <br> (90.000001, 89, 0) → (110.000001, 99, 7) |
| Repeated mixed-unit block | (88, 55, 10) → (98, 75, 15) <br> (88, 90, 10) → (98, 110, 17) <br> (200, 0, 0) → (220, 10, 5) |

The middle repeated block is mirrored. Its edited leaf and parent have their own Core resources. The first and third leaves still reference the same unedited mesh.

## PrusaSlicer GUI acceptance

Release verification is pending. Open each checked-in acceptance file separately in the PrusaSlicer window. Record the slicer version, file hash, displayed dimensions, whether a rescaling prompt appeared, whether manual rescaling was used, and the result. A passing observation requires the expected dimensions on first open, without a rescaling prompt or manual rescaling.

| File | Observed GUI version and dimensions | Rescaling prompt | Manual rescaling | Result |
| --- | --- | --- | --- | --- |
| created.3mf | Pending | Pending | Pending | Pending |
| centimeter.3mf | Pending | Pending | Pending | Pending |
