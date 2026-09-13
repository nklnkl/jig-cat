"""Stage 1: run SAM automatic mask generation once, cache masks to npz."""
import sys, time, numpy as np, cv2, torch
from segment_anything import sam_model_registry, SamAutomaticMaskGenerator

# torchvision NMS CUDA op is unavailable in this install; run NMS on CPU.
import torchvision.ops.boxes as _boxes
import segment_anything.automatic_mask_generator as _amg
_orig = _boxes.batched_nms
def _cpu_nms(boxes, scores, idxs, iou_threshold):
    return _orig(boxes.cpu(), scores.cpu(), idxs.cpu(), iou_threshold).to(boxes.device)
_amg.batched_nms = _cpu_nms

IMG = sys.argv[1]
OUT = sys.argv[2]
CKPT = sys.argv[3]

img = cv2.cvtColor(cv2.imread(IMG), cv2.COLOR_BGR2RGB)
print("image", img.shape, flush=True)
sam = sam_model_registry["vit_h"](checkpoint=CKPT).to("cuda")
gen = SamAutomaticMaskGenerator(
    sam,
    points_per_side=64,
    points_per_batch=128,
    pred_iou_thresh=0.80,
    stability_score_thresh=0.88,
    crop_n_layers=1,
    crop_n_points_downscale_factor=2,
    min_mask_region_area=400,
)
t = time.time()
masks = gen.generate(img)
print("masks", len(masks), "in", round(time.time() - t, 1), "s", flush=True)
segs = np.stack([m["segmentation"] for m in masks]).astype(np.uint8)
meta = np.array([[m["area"], m["predicted_iou"], m["stability_score"], *m["bbox"]] for m in masks], dtype=np.float32)
np.savez_compressed(OUT, segs=np.packbits(segs, axis=-1), shape=np.array(segs.shape), meta=meta)
print("saved", OUT, flush=True)
