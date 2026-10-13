"""Build-time: derive binary templates for the 2 Font + 2 TMP_FontAsset objects in the
original macOS resources.assets, so the installer can rebuild them with system fonts.

usage: make_templates.py <orig Data dir> <out json>
"""
import base64, json, os, struct, sys
sys.path.insert(0, os.path.dirname(__file__))
import ttg
from UnityPy.helpers import TypeTreeHelper
from UnityPy.streams import EndianBinaryWriter

D, OUT = sys.argv[1:3]
RES = os.path.join(D, 'resources.assets')
FONTS = {4055: 10649, 4054: 10650}  # Font pathID -> TMP_FontAsset pathID
B64 = lambda b: base64.b64encode(b).decode()


def ustr(s):
    b = s.encode()
    return struct.pack('<i', len(b)) + b + b'\0' * (-len(b) % 4)


env = ttg.load(RES, D)
f = list(env.files.values())[0]
DO = f.header.data_offset
objs = sorted(f.objects.values(), key=lambda o: o.byte_start)
for a, b in zip(objs, objs[1:]):
    assert b.byte_start == (a.byte_start + a.byte_size + 15) // 16 * 16
assert objs[-1].byte_start + objs[-1].byte_size == os.path.getsize(RES)

meta = open(RES, 'rb').read(DO)
TABLE = 4512
for k, pid in enumerate(sorted(f.objects)):
    o = f.objects[pid]
    assert struct.unpack('<qQI', meta[TABLE + 24 * k:TABLE + 24 * k + 20]) == (pid, o.byte_start - DO, o.byte_size)
assert struct.unpack('>Q', meta[24:32])[0] == os.path.getsize(RES)

out = {'dataOffset': DO, 'tableOffset': TABLE, 'entryCount': len(f.objects), 'fileSizeOffset': 24,
       'fonts': []}

for font_id, fa_id in FONTS.items():
    fo = f.objects[font_id]
    raw = fo.get_raw_data()
    fd = fo.read_typetree()
    data = bytes(fd['m_FontData'])
    name = ustr(fd['m_Name'])
    assert raw.startswith(name)
    ls_off = len(name)
    assert struct.unpack('<f', raw[ls_off:ls_off + 4])[0] == struct.unpack('<f', struct.pack('<f', fd['m_LineSpacing']))[0]
    dpos = raw.find(struct.pack('<I', len(data)) + data[:64])
    head = raw[:dpos]
    t = dpos + 4 + len(data)
    t += -t % 4
    # tail: m_Ascent f32, m_Descent f32, m_DefaultStyle i32, m_FontNames vector<string>, rest
    names = ustr(fd['m_FontNames'][0])
    assert struct.unpack('<i', raw[t + 12:t + 16])[0] == 1 and raw[t + 16:t + 16 + len(names)] == names
    rest = raw[t + 16 + len(names):]

    fa = f.objects[fa_id]
    d = fa.read_typetree()
    for k in d['m_FontFeatureTable']:
        d['m_FontFeatureTable'][k] = []
    w = EndianBinaryWriter(endian='<')
    TypeTreeHelper.write_typetree(d, fa._get_typetree_node(), w, fa.assets_file)
    fab = w.bytes
    face = d['m_FaceInfo']
    fam = ustr(face['m_FamilyName']) + ustr(face['m_StyleName'])
    i = fab.find(struct.pack('<i', face['m_FaceIndex']) + fam)
    assert i > 0 and fab.find(struct.pack('<i', face['m_FaceIndex']) + fam, i + 1) < 0
    pre = fab[:i + 4]
    nums = fab[i + 4 + len(fam):i + 4 + len(fam) + 72]
    suf = fab[i + 4 + len(fam) + 72:]
    vals = struct.unpack('<ffi' + 'f' * 15, nums)
    assert abs(vals[0] - face['m_PointSize']) < 1e-4 and abs(vals[-1] - face['m_TabWidth']) < 1e-4

    out['fonts'].append({
        'fontPathID': font_id, 'fontAssetPathID': fa_id,
        'fontHead': B64(head), 'lineSpacingOffset': ls_off,
        'defaultStyle': B64(raw[t + 8:t + 12]), 'fontRest': B64(rest), 'fontSize': fd['m_FontSize'],
        'assetPrefix': B64(pre), 'assetSuffix': B64(suf), 'faceNumbers': B64(nums),
        'origFontSize': fo.byte_size, 'origAssetSize': fa.byte_size,
    })
    print(font_id, 'head', len(head), 'rest', len(rest), '| asset', fa_id, 'pre', len(pre), 'suf', len(suf))

json.dump(out, open(OUT, 'w'), indent=1)
