# Cat-piece segmentation tools

Splits a "wall of cats" source image into one puzzle piece per cat. Every pixel of the
source belongs to exactly one piece; background between cats is given to the nearest cat,
and yarn balls are absorbed whole into the cat they border most.

## Requirements

- Python 3.12, NVIDIA GPU (tested on an RTX 3080 Ti, Godot is not involved here)
- `py -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124`
- `py -m pip install opencv-python scipy scikit-image segment-anything`
- SAM ViT-H checkpoint (2.5 GB) in `tools/segment/models/sam_vit_h_4b8939.pth`, from
  https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth (git-ignored)

## Pipeline

1. `seg_generate.py SOURCE.png masks.npz models/sam_vit_h_4b8939.pth`
   Runs Segment Anything's automatic mask generator once (about 5 minutes) and caches
   every candidate mask. Re-run only when the source image changes.
2. `seg_partition.py SOURCE.png masks.npz OUT_DIR 12000 200000 0.3 edits.json`
   Picks cat-sized masks (12k to 200k px), rejects masks that overlap an already kept
   one by more than 30%, applies the hand edits, fills gaps by nearest cat, smooths the
   borders, renumbers pieces in reading order, and writes:
   - `piece_NNN.png` — RGBA cutout, cropped to its bounding box
   - `manifest.json` — per piece: id, x, y, w, h (bbox in source pixels), cx, cy, area
   - `overlay.png` and `overlay_q0..3.png` — numbered review images
   - `label.npy` — the full label map (which piece owns each pixel)
3. Review the overlays, then fix mistakes with `edits.json` and re-run step 2.

## edits.json

Mask indices refer to the cached SAM masks in `masks.npz`. Find them with
`mask_browser.py SOURCE.png masks.npz sheet.png MIN_AREA MAX_AREA [x0 y0 x1 y1]`
(a contact sheet of masks in a region) and `zoom.py SOURCE.png OUT_DIR/overlay.png prefix
name,x,y,r ...` (side-by-side zoom of source and overlay).

- `force_mask_idx` — masks to keep as pieces regardless of size or score
- `drop_mask_idx` — masks never to use
- `merge` — pairs `[a, b]`: piece from mask b is joined into the piece from mask a
- `absorb_masks` — masks (yarn balls, stray paws) that are never pieces; each is given
  whole to the neighbouring piece sharing the longest border. Near-duplicate masks of
  these are dropped automatically.

Each puzzle keeps its own edits file next to the tools: `puzzles/<name>.edits.json`.
