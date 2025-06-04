#!/usr/bin/env python3
import os, glob
import pandas as pd
import numpy as np

RAW_DIR = "raw"
OUT_CSV = "all_windows.csv"
WINDOW_S = 2          # seconds
FS = 50               # Hz
STEP = FS             # 1-second hop (50% overlap)

def window_features(arr):
    # arr shape: (N, 6) for ax,ay,az,gx,gy,gz
    feats = []
    # mean & var for each of 6 channels
    feats += list(arr.mean(axis=0))
    feats += list(arr.var(axis=0))
    # accelerometer magnitude stats
    mag = np.linalg.norm(arr[:, :3], axis=1)
    feats += [mag.mean(), mag.var()]
    return feats

rows = []
header = []
# build header once
ch = ['ax','ay','az','gx','gy','gz']
for c in ch: header += [f"{c}_mean", f"{c}_var"]
header += ["mag_mean","mag_var"]
header += ["label"]

for path in glob.glob(os.path.join(RAW_DIR,"*.csv")):
    label = os.path.splitext(os.path.basename(path))[0]
    df = pd.read_csv(path, names=["ts"]+ch+["rotX","rotY","rotZ","lbl"], header=None)
    data = df[ch].to_numpy()
    N = len(data)
    for start in range(0, N - WINDOW_S*FS + 1, STEP):
        win = data[start:start+WINDOW_S*FS]
        feats = window_features(win)
        rows.append(feats + [label])

out = pd.DataFrame(rows, columns=header)
out.to_csv(OUT_CSV, index=False)
print(f"✅ Wrote {len(rows)} windows to {OUT_CSV}")

