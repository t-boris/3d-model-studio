# Import fixtures

Open each file from the workspace toolbar or with Command-O. Drag to orbit the block and scroll to zoom.

| File | Source units | Expected model-space bounds (X, Y, Z) |
| --- | --- | --- |
| [block.stl](block.stl) | Choose millimeters | (0, 0, 0) to (20, 10, 5) mm |
| [block.obj](block.obj) | Choose millimeters | (0, 0, 0) to (20, 10, 5) mm |
| [block.3mf](block.3mf) | Declares centimeters | (0, 0, 0) to (2, 1, 0.5) cm |

Each block has eight shared vertices, 12 outward-facing triangles and 18 undirected edges. Each edge belongs to two faces. Face IDs 0–1 form the bottom, 2–3 the top, 4–5 the front (minimum Y), 6–7 the right, 8–9 the back and 10–11 the left. IDs follow triangle order in the file. Vertex numbers can differ between formats.

The STL repeats corners in its facets. The OBJ uses relative vertex indices and normal references. The 3MF start part is `3D/block.model`. Its component rotates the local mesh 90° about Z, then the build item translates it 2 cm along X. All three files should occupy the same physical space after import.

## Reuse in I-4 and I-6

Starting from a fresh Open for each workflow, set the block height to 7 mm while keeping its bottom at Z = 0.

For the manual edit, choose **Reshape Surface**, rotate until you can see the top, and click both top triangles. Both should be highlighted. Choose **Z**, enter **2 mm**, and click **Apply**. Check Height (Z) in the dimension controls. Pin it, then try another 1 mm Z offset. The alert should identify the pinned height, and the selected top should stay at 7 mm.

To try the other tools, unpin the height. Choose **Extrude** with the same two top triangles selected and apply **2 mm**. Height should reach 9 mm with 12 vertices and 20 triangles. Choose **Move Point**, click near a top corner, and apply **−1 mm** along Z (type `-1`). Its measured Z coordinate should become 8 mm, while the other top corners stay at 9 mm.

Run `Tests/run-manual-edit-checks.sh` to exercise the three operations and viewport geometry against all fixtures and a new block using the Swift interpreter.

For the conversational edit, choose **Ask Agent → Revise Entire Model…** and request “Make this block 7 mm tall. Keep the bottom at Z = 0 and keep the width and depth.” Review the preview and requested spans, then choose **Apply to Model**. In the same sheet request “Make it 0.9 cm tall”. Applying that revision should set the height to 9 mm. The first edit uses the same active indexed mesh as the manual workflow. After the first edit the expected physical extents are 20 × 10 × 7 mm. The top of the 3MF model should read 0.7 cm in its source unit. A height adjustment by moving the four shared top vertices preserves all 12 face IDs and the connectivity above.

Run `Tests/run-provider-checks.sh` for the offline conversation matrix across all three configured agents and all three imports.

To check failure handling, open a valid block, adjust the view, then open a copy of the OBJ containing an out-of-range face index. The error should name the file and offending line. Dismiss it and verify the original block, units and camera position. Canceling the unit picker while opening a second block should also preserve the first.

## Selected-face review

Open a fresh block, choose **Reshape Surface**, select the two top triangles and choose **Ask Agent → Edit Selected Faces…**. Ask to raise the top to a whole-model height of 7 mm by moving its four corners. For a proposal that moves those shared corners, the review should show the affected side triangles in orange and the affected selected top in indigo. Any earlier approval to share neighboring geometry applies only to reading it.

Choose **Decline Edit** and verify the height remains 5 mm. Submit the same request again and review the new proposal. **Confirm Outside Changes** should apply a candidate that measures 7 mm and satisfies all active pins. To exercise rejection, start with a fresh import, pin its 5 mm height and confirm a proposal that raises it to 7 mm. The workspace should retain the original mesh and identify the pinned height conflict.

## Multipart 3MF assemblies

Both slicer fixtures are original project saves. Each slicer arranged two copies of this repository's 20 × 10 × 5 mm block on a plate and wrote a start model, its relationships, and two referenced mesh parts. The table gives the minimum and maximum corner of each occurrence in build order, in millimeters.

| Fixture | First block | Second block |
| --- | --- | --- |
| [Bambu Studio 02.09.01.70](Assemblies/bambu-blocks.3mf) | (90.00001, 100.99999, 0) to (110.00001, 110.99999, 5) | (90, 89.00003, 0) to (110, 99.00003, 5) |
| [OrcaSlicer 2.5.2](Assemblies/orca-blocks.3mf) | (90, 101, 0) to (110, 111, 5) | (90.000001, 89, 0) to (110.000001, 99, 5) |

Provenance for both saves is 2026-11-25 on macOS. The CLI inputs were copies of `Fixtures/Import/block.stl` named `block.stl` and `twin.stl`, supplied in that order with `--arrange 1 --export-3mf` and a temporary data directory. Each file's root XML records the producer version. OrcaSlicer also writes a BambuStudio compatibility version in its Application metadata. The SHA-256 digests of the archived saves are `23af39a2f14e72b83c617b5272539e8f3c1ba4c880bdd44062d47df6a4a06f5a` (Bambu) and `f9d96e94d55157e3bf01fd1e1e4908773ee6f6c25f9bc53eeb2f29bfb9760fa8` (Orca).

The [synthetic repeated-block fixture](Assemblies/repeated-block.3mf) places one centimeter mesh three times in a start model with the default millimeter unit. Its first build item rotates two nested occurrences, one mirrored. Its second build item references the child part directly. Expected bounds in occurrence order are (88, 55, 10) to (98, 75, 15), (88, 90, 10) to (98, 110, 15), and (200, 0, 0) to (220, 10, 5) mm. Object ID 1 occurs in both model parts.

Run `Tests/run-assembly-checks.sh` from the checkout. It checks each occurrence's coordinates, eight shared vertices, twelve outward-facing triangles, source mapping and stable face IDs. It sends each imported mesh through the SceneKit viewport, a manual point edit and a scripted conversational revision, and checks that the other occurrences keep their positions. The same suite opens invalid packages over an edited, pinned workspace and exercises cancellation at both unit prompts.
