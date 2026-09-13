"""Zoom: side-by-side crops of original and overlay around given centers.
usage: zoom.py IMG OVERLAY OUT_PREFIX name,x,y,r [name,x,y,r ...]"""
import sys, cv2, numpy as np
IMG, OVL, PRE = sys.argv[1], sys.argv[2], sys.argv[3]
img = cv2.imread(IMG); ovl = cv2.imread(OVL)
H, W = img.shape[:2]
for spec in sys.argv[4:]:
    name, x, y, r = spec.split(","); x, y, r = int(x), int(y), int(r)
    x0, x1, y0, y1 = max(0, x - r), min(W, x + r), max(0, y - r), min(H, y + r)
    a, b = img[y0:y1, x0:x1], ovl[y0:y1, x0:x1]
    both = np.concatenate([a, b], axis=1)
    s = 1024 / both.shape[1]
    both = cv2.resize(both, (1024, int(both.shape[0] * s)), interpolation=cv2.INTER_AREA)
    cv2.putText(both, f"{name} @({x},{y}) r{r}", (6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
    cv2.putText(both, f"{name} @({x},{y}) r{r}", (6, 22), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 1)
    cv2.imwrite(f"{PRE}_{name}.png", both)
    print("wrote", f"{PRE}_{name}.png")
