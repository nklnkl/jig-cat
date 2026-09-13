"""Debug: contact sheet of raw SAM masks whose bbox centre lies in a region, within an area range.
usage: mask_browser.py IMG NPZ OUT LO HI [x0 y0 x1 y1]"""
import sys, numpy as np, cv2
IMG, NPZ, OUT, LO, HI = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
region = [int(v) for v in sys.argv[6:10]] if len(sys.argv) >= 10 else None
img = cv2.imread(IMG)
d = np.load(NPZ)
shape = tuple(d["shape"])
segs = np.unpackbits(d["segs"], axis=-1)[..., :shape[-1]].astype(bool)
meta = d["meta"]
idx = []
for i in range(len(meta)):
    a, _, _, x, y, w, h = meta[i]
    if not (LO <= a <= HI):
        continue
    if region:
        cx, cy = x + w / 2, y + h / 2
        if not (region[0] <= cx <= region[2] and region[1] <= cy <= region[3]):
            continue
    idx.append(i)
print("masks in range", len(idx))
T = 200
tiles = []
for i in idx:
    x, y, w, h = meta[i, 3:7].astype(int)
    crop = img[y:y + h, x:x + w].copy()
    crop[~segs[i][y:y + h, x:x + w]] //= 4
    s = (T - 20) / max(w, h)
    crop = cv2.resize(crop, (max(1, int(w * s)), max(1, int(h * s))))
    tile = np.zeros((T, T, 3), np.uint8)
    tile[:crop.shape[0], :crop.shape[1]] = crop
    cv2.putText(tile, f"#{i} a{int(meta[i, 0] // 1000)}k @{x + w // 2},{y + h // 2}", (2, T - 4), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (0, 255, 255), 1)
    tiles.append(tile)
cols = 6
rows = max(1, (len(tiles) + cols - 1) // cols)
sheet = np.zeros((rows * T, cols * T, 3), np.uint8)
for n, t in enumerate(tiles):
    sheet[(n // cols) * T:(n // cols + 1) * T, (n % cols) * T:(n % cols + 1) * T] = t
cv2.imwrite(OUT, sheet)
