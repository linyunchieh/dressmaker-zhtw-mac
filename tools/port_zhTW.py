"""Port the Windows Dressmaker zh-TW patch to the macOS build.

usage: port_zhTW.py <mac Data dir> <payload dir> <out dir> [--font mac|sourcehan]
Reads original Mac files, writes patched copies under <out dir> with the same relative paths.
"""
import hashlib, json, os, struct, sys, io
sys.path.insert(0, os.path.dirname(__file__))
import ttg
from fontTools.ttLib import TTFont

D, PAY, OUT = sys.argv[1:4]
FONT_MODE = sys.argv[sys.argv.index('--font') + 1] if '--font' in sys.argv else 'mac'

AA = 'StreamingAssets/aa/StandaloneOSX/'
STR_BUNDLE = AA + 'localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle'
LOC_BUNDLE = AA + 'localization-locales_assets_all.bundle'
CATALOG = 'StreamingAssets/aa/catalog.bin'
DLL = 'Managed/Assembly-CSharp.dll'
RES = 'resources.assets'

MAC_ORIG = {
    DLL: '2e35816ac2ad8cf85b4b5b2761ce35e58e4265d2899d8b81f412305ac177d7c9',
    RES: '9e81edc6776e96196b71e0f71504f1e75fb711da15f2dbd4ee57a559e052426d',
    CATALOG: '6c13657106952049563c4c7c92512273081ad9060fbdf9d6f5f83ea8f4b186ef',
    STR_BUNDLE: '9a0da53a08540e2522853b8cfdcaa0fec81445ec08a7bb45a2913132ccc0a2cd',
    LOC_BUNDLE: '3a5ff4b32f86759049ab45262ec4bd8d3dc2ea6896efc8404850b618a7c5c525',
}

PINGFANG = '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc'
SONGTI = '/System/Library/Fonts/Supplemental/Songti.ttc'
# Font pathID -> (FontAsset pathID, source)
FONTS = {
    4055: (10649, (PINGFANG, 2)),   # SourceHanSansSC-Regular  -> PingFang TC Regular
    4054: (10650, (SONGTI, 7)),     # SourceHanSerifSC-Regular -> Songti TC Regular
}
LOCALE_NAMES = {'Chinese (Simplified) (zh-Hans)': '繁體中文', 'Japanese (ja)': '日本語', 'English (en)': 'English'}


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def out_path(rel):
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


for rel, h in MAC_ORIG.items():
    got = sha(os.path.join(D, rel))
    if got != h:
        sys.exit(f'hash mismatch {rel}: {got}')


def win_payload_tables():
    env = ttg.load(os.path.join(PAY, 'f0.bin'), D)
    return {o.read_typetree()['m_Name']: {e['m_Id']: e['m_Localized'] for e in o.read_typetree()['m_TableData']}
            for o in env.objects if o.type.name == 'MonoBehaviour' and 'm_TableData' in o.read_typetree()}


def port_string_tables():
    tc = win_payload_tables()
    env = ttg.load(os.path.join(D, STR_BUNDLE), D)
    n = 0
    for o in env.objects:
        if o.type.name != 'MonoBehaviour':
            continue
        d = o.read_typetree()
        if 'm_TableData' not in d:
            continue
        src = tc[d['m_Name']]
        for e in d['m_TableData']:
            if e['m_Id'] in src and e['m_Localized'] != src[e['m_Id']]:
                e['m_Localized'] = src[e['m_Id']]
                n += 1
        o.save_typetree(d)
    open(out_path(STR_BUNDLE), 'wb').write(env.file.save(packer='original'))
    print('string entries replaced', n)


def port_locales():
    env = ttg.load(os.path.join(D, LOC_BUNDLE), D)
    for o in env.objects:
        if o.type.name != 'MonoBehaviour':
            continue
        d = o.read_typetree()
        if d.get('m_LocaleName') in LOCALE_NAMES:
            d['m_LocaleName'] = LOCALE_NAMES[d['m_LocaleName']]
            o.save_typetree(d)
    open(out_path(LOC_BUNDLE), 'wb').write(env.file.save(packer='original'))
    print('locales done')


def load_font(path, index):
    f = TTFont(path, fontNumber=index, lazy=True)
    buf = io.BytesIO()
    f.save(buf, reorderTables=False)
    return buf.getvalue(), TTFont(io.BytesIO(buf.getvalue()))


def glyph_top(font, ch):
    gs = font.getGlyphSet()
    name = font.getBestCmap().get(ord(ch))
    from fontTools.pens.boundsPen import BoundsPen
    pen = BoundsPen(gs)
    gs[name].draw(pen)
    return pen.bounds[3]


def update_face(face, font):
    upm = font['head'].unitsPerEm
    s = face['m_PointSize'] / upm
    hh, post = font['hhea'], font['post']
    face['m_FamilyName'] = font['name'].getDebugName(1)
    face['m_StyleName'] = font['name'].getDebugName(2)
    face['m_UnitsPerEM'] = upm
    face['m_AscentLine'] = hh.ascent * s
    face['m_DescentLine'] = hh.descent * s
    face['m_LineHeight'] = (hh.ascent - hh.descent + hh.lineGap) * s
    face['m_CapLine'] = round(glyph_top(font, 'H') * s)
    face['m_MeanLine'] = round(glyph_top(font, 'x') * s)
    face['m_SuperscriptOffset'] = face['m_AscentLine']
    face['m_SubscriptOffset'] = face['m_DescentLine']
    face['m_UnderlineOffset'] = post.underlinePosition * s
    face['m_UnderlineThickness'] = post.underlineThickness * s


def port_resources():
    env = ttg.load(os.path.join(D, RES), D)
    f = list(env.files.values())[0]
    for font_id, (fa_id, (path, idx)) in FONTS.items():
        fo = f.objects[font_id]
        fd = fo.read_typetree()
        if FONT_MODE == 'mac':
            data, tt = load_font(path, idx)
        else:  # Source Han TC bytes shipped in the Windows patch
            data = open(os.path.join(PAY, f'sourcehan_{font_id}.otf'), 'rb').read()
            tt = TTFont(io.BytesIO(data))
        fam = tt['name'].getDebugName(1)
        upm = tt['head'].unitsPerEm
        hh = tt['hhea']
        fd['m_FontData'] = list(data)
        fd['m_FontNames'] = [fam]
        size = fd['m_FontSize']
        fd['m_Ascent'] = hh.ascent * size / upm
        fd['m_Descent'] = hh.descent * size / upm
        fd['m_LineSpacing'] = (hh.ascent - hh.descent + hh.lineGap) * size / upm
        fo.save_typetree(fd)

        fa = f.objects[fa_id]
        d = fa.read_typetree()
        update_face(d['m_FaceInfo'], tt)
        # Feature records are keyed by glyph IDs of the old font; they would map to wrong glyphs.
        for k in d['m_FontFeatureTable']:
            d['m_FontFeatureTable'][k] = []
        fa.save_typetree(d)
        print('font', font_id, '->', fam, len(data), 'bytes; face', json.dumps(d['m_FaceInfo'], ensure_ascii=False))
    open(out_path(RES), 'wb').write(f.save())


def port_dll():
    b = bytearray(open(os.path.join(D, DLL), 'rb').read())
    # LanguageSelectorPopup.NativeName: brtrue.s 7 -> pop; nop  (always return locale.LocaleName)
    off = 162828
    assert b[off - 16:off + 2] == bytes.fromhex('026f6904000a0b1201287004000a0a062d07'), 'IL mismatch'
    b[off:off + 2] = b'\x26\x00'
    open(out_path(DLL), 'wb').write(b)
    print('dll done')


def port_catalog():
    b = bytearray(open(os.path.join(D, CATALOG), 'rb').read())
    # record layout: ... crc u32, size u32, 0x726, 0x767 ; zero CRC of the two rewritten bundles
    tail = bytes.fromhex('2607000067070000')
    for size in (os.path.getsize(os.path.join(D, LOC_BUNDLE)), os.path.getsize(os.path.join(D, STR_BUNDLE))):
        pat = struct.pack('<I', size) + tail
        i = b.find(pat)
        assert i > 0 and b.find(pat, i + 1) < 0, f'catalog record for size {size}'
        b[i - 4:i] = b'\0\0\0\0'
    open(out_path(CATALOG), 'wb').write(b)
    print('catalog done')


port_dll()
port_catalog()
port_locales()
port_string_tables()
port_resources()
for rel in MAC_ORIG:
    print(sha(os.path.join(OUT, rel)), rel)
