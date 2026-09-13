"""Stage 2: pick cat-level masks, partition the whole image, export pieces + overlays."""
import sys, os, json, numpy as np, cv2
from scipy import ndimage as ndi

IMG, NPZ, OUTDIR = sys.argv[1], sys.argv[2], sys.argv[3]
MIN_AREA, MAX_AREA = int(sys.argv[4]), int(sys.argv[5])
OVERLAP_REJECT = float(sys.argv[6])  # reject a mask if this fraction of it is already claimed
EDITS = sys.argv[7] if len(sys.argv) > 7 else None
os.makedirs(OUTDIR, exist_ok=True)

img = cv2.cvtColor(cv2.imread(IMG), cv2.COLOR_BGR2RGB)
H, W = img.shape[:2]
d = np.load(NPZ)
shape = tuple(d["shape"])
segs = np.unpackbits(d["segs"], axis=-1)[..., :shape[-1]].astype(bool)
meta = d["meta"]  # area, iou, stab, x, y, w, h
print("loaded masks", segs.shape[0])

edits = json.load(open(EDITS)) if EDITS and os.path.exists(EDITS) else {}
absorb_idx = list(edits.get("absorb_masks", []))
merge_pairs = list(edits.get("merge", []))
drop_idx = set(edits.get("drop_mask_idx", [])) | set(absorb_idx)
force_idx = list(edits.get("force_mask_idx", []))
# extra masks supplied as PNGs (from point-prompt runs): list of file paths
extra_files = edits.get("extra_mask_files", [])
if extra_files:
    extra = np.stack([cv2.imread(f, cv2.IMREAD_GRAYSCALE) > 127 for f in extra_files])
    segs = np.concatenate([segs, extra])
    em = np.array([[m.sum(), 1.0, 1.0, 0, 0, 0, 0] for m in extra], dtype=np.float32)
    meta = np.concatenate([meta, em])
    force_idx = list(range(len(meta) - len(extra), len(meta))) + force_idx

area = meta[:, 0]
score = meta[:, 1] * meta[:, 2]
cand = [i for i in range(len(meta)) if MIN_AREA <= area[i] <= MAX_AREA and i not in drop_idx]
# drop near-duplicates of absorbed / dropped masks (SAM emits several copies of the same object)
for j in list(absorb_idx) + list(edits.get("drop_mask_idx", [])):
    mj = segs[j]
    for i in list(cand):
        inter = (mj & segs[i]).sum()
        if inter / (mj.sum() + segs[i].sum() - inter) > 0.5:
            cand.remove(i)
            print("dropping duplicate", i, "of", j)
order = sorted(cand, key=lambda i: (-score[i], -area[i]))
order = [i for i in force_idx if i not in drop_idx] + [i for i in order if i not in force_idx]

claimed = np.zeros((H, W), bool)
kept = []
for i in order:
    m = segs[i]
    ov = (m & claimed).sum() / m.sum()
    if ov > OVERLAP_REJECT:
        continue
    kept.append(i)
    claimed |= m
print("kept masks", len(kept))

label = np.full((H, W), -1, np.int32)
for k, i in enumerate(kept):
    label[(label == -1) & segs[i]] = k
# merges: sam idx pairs -> second piece relabelled into first
pos = {i: k for k, i in enumerate(kept)}
for a, b in merge_pairs:
    if a in pos and b in pos:
        label[label == pos[b]] = pos[a]
        print("merged sam", b, "into", a)
    else:
        print("WARN merge pair not both kept", a, b)
# absorbs: whole mask goes to the neighbouring piece sharing the longest border
absorbed = []
for i in absorb_idx:
    m = segs[i]
    ring = cv2.dilate(m.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool) & ~m
    labs = label[ring]
    labs = labs[labs >= 0]
    if labs.size == 0:
        print("WARN absorb", i, "has no labelled neighbour"); continue
    tgt = int(np.bincount(labs).argmax())
    label[m] = tgt
    label[ring & (label == -1)] = tgt  # bridge any unlabelled gap so the blob stays connected
    absorbed.append((i, tgt))
    print("absorbed sam", i, "into piece of sam", kept[tgt])
# compact labels (merges leave holes)
used = np.unique(label[label >= 0])
remap = {int(v): n for n, v in enumerate(used)}
kept = [kept[int(v)] for v in used]
lut = np.full(label.max() + 2, -1, np.int32)
for v, n in remap.items():
    lut[v] = n
label = np.where(label >= 0, lut[np.clip(label, 0, None)], -1)


def fix_connectivity(label):
    for k in range(label.max() + 1):
        cc, n = ndi.label(label == k)
        if n > 1:
            sizes = ndi.sum(np.ones_like(cc), cc, range(1, n + 1))
            main = int(np.argmax(sizes)) + 1
            label[(cc > 0) & (cc != main)] = -1
    return label


def fill_nearest(label):
    if (label == -1).any():
        _, (iy, ix) = ndi.distance_transform_edt(label == -1, return_indices=True)
        label = label[iy, ix]
    return label


def smooth(label, r=4):
    out = label.copy()
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)).astype(np.float32)
    k /= k.sum()
    best = np.zeros(label.shape, np.float32)
    for v in range(label.max() + 1):
        f = cv2.filter2D((label == v).astype(np.float32), -1, k)
        upd = f > best
        out[upd] = v
        best[upd] = f[upd]
    return out


label = fix_connectivity(label)
print("unassigned px before fill", int((label == -1).sum()))
label = fill_nearest(label)
label = smooth(label)
label = fill_nearest(fix_connectivity(label))

# renumber pieces in reading order (row bands of 200px, then left to right)
n = label.max() + 1
cy = ndi.mean(np.indices(label.shape)[0], label, range(n))
cx = ndi.mean(np.indices(label.shape)[1], label, range(n))
order = sorted(range(n), key=lambda k: (int(cy[k] // 200), cx[k]))
lut = np.zeros(n, np.int32)
for new_k, old_k in enumerate(order):
    lut[old_k] = new_k
label = lut[label]
kept = [kept[k] for k in order]

np.save(os.path.join(OUTDIR, "label.npy"), label)

# --- cat-only alpha: pieces keep just the cat pixels; leftover background is a board layer
catmask = np.zeros((H, W), bool)
for i in kept:
    catmask |= segs[i]
for i in absorb_idx:
    catmask |= segs[i]
k5 = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
catmask = cv2.morphologyEx(catmask.astype(np.uint8), cv2.MORPH_CLOSE, k5)
catmask = cv2.morphologyEx(catmask, cv2.MORPH_OPEN, k5).astype(bool)
piece_alpha = np.zeros((H, W), bool)
for k in range(label.max() + 1):
    m = ndi.binary_fill_holes((label == k) & catmask)
    piece_alpha |= m
    label = np.where(m, k, label)
alpha_of = lambda k: ((label == k) & piece_alpha)
bg = np.dstack([img, ((~piece_alpha) * 255).astype(np.uint8)])
cv2.imwrite(os.path.join(OUTDIR, "background.png"), cv2.cvtColor(bg, cv2.COLOR_RGBA2BGRA))
print("background px", int((~piece_alpha).sum()), "of", H * W)
for i, tgt in absorbed:
    vals, cnts = np.unique(label[segs[i]], return_counts=True)
    comp = sorted(zip(cnts.tolist(), vals.tolist()), reverse=True)[:3]
    print("absorb check sam", i, "->", [(int(v), round(c / segs[i].sum(), 2)) for c, v in comp])
manifest = []
rng = np.random.default_rng(7)
colors = rng.integers(60, 255, (len(kept), 3))
overlay = img.copy()
edges = np.zeros((H, W), bool)
for k in range(len(kept)):
    m = alpha_of(k)
    ys, xs = np.where(m)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([img[y0:y1, x0:x1], (m[y0:y1, x0:x1] * 255).astype(np.uint8)])
    cv2.imwrite(os.path.join(OUTDIR, f"piece_{k:03d}.png"), cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA))
    manifest.append({"id": k, "sam_mask_idx": int(kept[k]), "x": int(x0), "y": int(y0), "w": int(x1 - x0), "h": int(y1 - y0),
                     "cx": int(xs.mean()), "cy": int(ys.mean()), "area": int(m.sum())})
    er = cv2.erode(m.astype(np.uint8), np.ones((3, 3), np.uint8))
    edges |= m & ~er.astype(bool)
    overlay[m] = (overlay[m] * 0.75 + colors[k] * 0.25).astype(np.uint8)
edges = cv2.dilate(edges.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
overlay[edges] = (255, 255, 255)
for e in manifest:
    cv2.putText(overlay, str(e["id"]), (e["cx"] - 14, e["cy"] + 8), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 0), 5)
    cv2.putText(overlay, str(e["id"]), (e["cx"] - 14, e["cy"] + 8), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 0), 2)
cv2.imwrite(os.path.join(OUTDIR, "overlay.png"), cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR))
for qi, (qy, qx) in enumerate([(0, 0), (0, 1), (1, 0), (1, 1)]):
    crop = overlay[qy * H // 2:(qy + 1) * H // 2, qx * W // 2:(qx + 1) * W // 2]
    cv2.imwrite(os.path.join(OUTDIR, f"overlay_q{qi}.png"), cv2.cvtColor(crop, cv2.COLOR_RGB2BGR))
json.dump({"image": os.path.basename(IMG), "background": "background.png", "width": W, "height": H, "pieces": manifest},
          open(os.path.join(OUTDIR, "manifest.json"), "w"), indent=1)
areas = sorted(e["area"] for e in manifest)
print("pieces", len(manifest), "area min/med/max", areas[0], areas[len(areas) // 2], areas[-1])
