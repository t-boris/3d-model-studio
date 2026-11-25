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

Starting from a fresh Open for each workflow, set the block height to 7 mm while keeping its bottom at Z = 0. For the conversational edit, request “Make this block 7 mm tall. Keep the bottom at Z = 0 and keep the width and depth.” Both workflows should operate on the active indexed mesh. Expected physical extents are 20 × 10 × 7 mm. The top of the 3MF model should read 0.7 cm in its source unit. A height adjustment by moving the four shared top vertices preserves all 12 face IDs and the connectivity above.

To check failure handling, open a valid block, adjust the view, then open a copy of the OBJ containing an out-of-range face index. The error should name the file and offending line. Dismiss it and verify the original block, units and camera position. Canceling the unit picker while opening a second block should also preserve the first.
