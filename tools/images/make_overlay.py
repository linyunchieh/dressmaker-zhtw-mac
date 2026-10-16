"""把重新排字後的完整貼圖拆成「只有改過的像素」的圖層，repo 只存這個，不存原版美術。

usage: make_overlay.py <原版 Data 資料夾> <名稱>=<完整繁中貼圖.png> ...
輸出 assets/images/<名稱>_overlay.png（改過的像素，其餘全透明）與 <名稱>_mask.png（改過的位置）。
tools/port_zhTW.py 會在 build 時從原版貼圖加上這兩張圖還原出完整貼圖，結果和原本的完整 PNG 逐像素相同。
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import numpy as np
from PIL import Image
import ttg

IMG_BUNDLE = 'StreamingAssets/aa/StandaloneOSX/localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle'
IMG_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'images')

D = sys.argv[1]
targets = dict(a.split('=', 1) for a in sys.argv[2:])
env = ttg.load(os.path.join(D, IMG_BUNDLE), D)
for o in env.objects:
    if o.type.name != 'Texture2D':
        continue
    t = o.read()
    if t.m_Name not in targets:
        continue
    orig = np.array(t.image.convert('RGBA'))
    new = np.array(Image.open(targets.pop(t.m_Name)).convert('RGBA'))
    assert orig.shape == new.shape, t.m_Name
    mask = (orig != new).any(2)
    overlay = np.where(mask[..., None], new, 0).astype(np.uint8)
    Image.fromarray(overlay).save(os.path.join(IMG_DIR, t.m_Name + '_overlay.png'), optimize=True)
    Image.fromarray(mask).save(os.path.join(IMG_DIR, t.m_Name + '_mask.png'), optimize=True)
    print(t.m_Name, f'改過 {mask.mean() * 100:.2f}% 像素')
assert not targets, f'找不到貼圖：{list(targets)}'
