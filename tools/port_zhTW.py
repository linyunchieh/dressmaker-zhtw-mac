"""Port the Windows Dressmaker zh-TW patch to the macOS build.

usage: port_zhTW.py <mac Data dir> <payload dir> <out dir> [--font mac|sourcehan]
Reads original Mac files, writes patched copies under <out dir> with the same relative paths.
"""
import hashlib, json, os, re, struct, sys, io
sys.path.insert(0, os.path.dirname(__file__))
import ids, terms, ttg
from fontTools.ttLib import TTFont

D, PAY, OUT = sys.argv[1:4]
FONT_MODE = sys.argv[sys.argv.index('--font') + 1] if '--font' in sys.argv else 'mac'

AA = 'StreamingAssets/aa/StandaloneOSX/'
STR_BUNDLE = AA + 'localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle'
LOC_BUNDLE = AA + 'localization-locales_assets_all.bundle'
IMG_BUNDLE = AA + 'localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle'
EN_BUNDLE = AA + 'localization-string-tables-english(en)_assets_all.bundle'
IMG_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'images')
# 換成繁中的圖片（Texture2D 名稱 → assets/images/<名稱>.png），由 tools/images/ 的腳本產生
IMAGES = ['flyer_scn', 'newspaperSprites_scn']
# 直接沿用遊戲內其他圖片（原始壓縮資料照搬）：簡中 Logo「针影裁梦」→ 英文 Logo
SHARED_BUNDLE = AA + 'localization-assets-shared_assets_all.bundle'
IMAGE_COPIES = {'gamelogo_scn': (SHARED_BUNDLE, 'gamelogo')}
CATALOG = 'StreamingAssets/aa/catalog.bin'
DLL = 'Managed/Assembly-CSharp.dll'
RES = 'resources.assets'

# Steam build 25936486
MAC_ORIG = {
    DLL: 'b6f0e991a3268613017d8f14e344932f2bb6758c9c6c3333faad56bd8527a8ca',
    RES: '35927cb82a84d005c4c08156c36fad2e02e29e80c383b4f2757ad99bfbcea39a',
    CATALOG: 'ff4008a2a541712dbcc1ad653f7e9fad64826084d7b72517e5740178e73ecd43',
    STR_BUNDLE: '342963966b18e85524389474d51b2c57ad6c1fcdfac9834391a08d8f15982cfa',
    LOC_BUNDLE: '3a5ff4b32f86759049ab45262ec4bd8d3dc2ea6896efc8404850b618a7c5c525',
    IMG_BUNDLE: 'ed83d6fd63765387f473493b9dc854a202596a66390e096db55501e5c64e2c82',
}

PINGFANG = '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc'
SONGTI = '/System/Library/Fonts/Supplemental/Songti.ttc'
# 系統字型（PostScript 名稱）-> 開發機上的字型檔（ttc, index）
FONT_FILES = {'PingFangTC-Regular': (PINGFANG, 2), 'STSongti-TC-Regular': (SONGTI, 7)}
# Windows 版譯文沒有（遊戲更新新增）或簡中原文已經改過的字串：(表名, id) -> 繁中
TC_OVERRIDES = {
    # build 25928714 新增
    ('Content_zh-Hans', 40645156016209920): '鏡頭平移',
    ('Content_zh-Hans', 41616726687600640): '衣身罩杯上片（左）',
    ('Content_zh-Hans', 41616726729543680): '衣身罩杯上片（右）',
    ('Content_zh-Hans', 41616726733737984): '衣身紐扣門襟·1',
    ('Content_zh-Hans', 41616726733737985): '衣身紐扣門襟·2',
    ('Content_zh-Hans', 41616726733737986): '衣身前紐扣門襟·1',
    ('Content_zh-Hans', 42112863878234112): '鏡頭環繞',
    ('Content_zh-Hans', 42112863882428416): '旋轉人台',
    ('Content_zh-Hans', 42112873286057984): '裙襬前拼片（右）',
    ('Content_zh-Hans', 43188215582920704): '下一頁',
    ('Content_zh-Hans', 43188215608086528): '上一頁',
    ('Tutorial_zh-Hans', 28632190920146944): '你也可以點擊<style=c1>部件名稱</style>鍵來看看可選的選項。',
    ('Tutorial_zh-Hans', 28632190932729856): '你可以透過<style=c1>前後翻頁</style>來瀏覽設計簿。',
    ('UI_zh-Hans', 28315391036997632): '丟棄布料',
    ('UI_zh-Hans', 40957591591829504): '減少動畫效果',
    ('UI_zh-Hans', 40960308741652480): '輪廓',
    ('UI_zh-Hans', 40960419022487552): '快速鑲邊',
    ('UI_zh-Hans', 41330588229251072): '遊戲玩法',
    ('UI_zh-Hans', 41330658513203200): '畫面',
    ('UI_zh-Hans', 41330715622846464): '音效',
    ('UI_zh-Hans', 41337045322510336): '光暈',
    ('UI_zh-Hans', 41383281541758976): '將從你的紀錄中永久刪除這件裙裝。確定嗎？',
    ('UI_zh-Hans', 41740693060554752): '出售',
    ('UI_zh-Hans', 42111338724442112): '剪刀',
    ('UI_zh-Hans', 42111338724442113): '丟棄布料',
    ('UI_zh-Hans', 42111338724442114): '切換縫份顯示',
    ('UI_zh-Hans', 42111338724442115): '將所有裁片放回庫存',
    # build 25928714 簡中原文改過
    ('Tutorial_zh-Hans', 1016171696142): '現在為一件<color=#0e85d9>職業</color>的服裝尋找合適的<style=c1>設計</style>與<style=c1>布料</style>。',
    ('Tutorial_zh-Hans', 1016171696158): '你可以透過按<color=#0e85d9>丟棄布料</color>鍵來丟棄已經使用的布料區域，為更多部件騰出空間。',
    ('UI_zh-Hans', 1457183857295378): '報酬：<sprite=0>{0}',
    ('UI_zh-Hans', 6234992911826944): '作為成衣出售',
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


def en_tables():
    env = ttg.load(os.path.join(D, EN_BUNDLE), D)
    return {(d['m_Name'].replace('_en', '_zh-Hans'), e['m_Id']): e['m_Localized']
            for d in (o.read_typetree() for o in env.objects if o.type.name == 'MonoBehaviour')
            if 'm_TableData' in d for e in d['m_TableData']}


def port_string_tables():
    tc = win_payload_tables()
    en = en_tables()
    env = ttg.load(os.path.join(D, STR_BUNDLE), D)
    n = 0
    missing = []
    for o in env.objects:
        if o.type.name != 'MonoBehaviour':
            continue
        d = o.read_typetree()
        if 'm_TableData' not in d:
            continue
        src = tc[d['m_Name']]
        for e in d['m_TableData']:
            new = TC_OVERRIDES.get((d['m_Name'], e['m_Id'])) or src.get(e['m_Id'])
            if new is None:
                missing.append((d['m_Name'], e['m_Id'], e['m_Localized']))
                continue
            key = (d['m_Name'], e['m_Id'])
            new = terms.fix(new, en.get(key, ''), key)  # 用語修正（tools/terms.py）
            if new != e['m_Localized']:
                e['m_Localized'] = new
                n += 1
        o.save_typetree(d)
    if missing:  # 遊戲更新新增的字串：補進 TC_OVERRIDES
        sys.exit('沒有繁中譯文：\n' + '\n'.join(map(repr, missing)))
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
    for font_id, (fa_id, ps) in ids.resource_ids(f)['fonts'].items():
        path, idx = FONT_FILES[ps]
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
    # ldarg.0 callvirt stloc.1 ldloca.s 1 call stloc.0 ldloc.0 brtrue.s 7 ...（metadata token 每版不同）
    il = re.compile(rb'\x02\x6f...\x0a\x0b\x12\x01\x28...\x0a\x0a\x06\x2d\x07\x02\x6f...\x0a\x2a\x06\x6f...\x0a\x2a', re.S)
    hits = [m.start() for m in il.finditer(b)]
    assert len(hits) == 1, f'IL mismatch {hits}'
    off = hits[0] + 16
    b[off:off + 2] = b'\x26\x00'
    open(out_path(DLL), 'wb').write(b)
    print('dll done')


def port_images():
    from PIL import Image
    env = ttg.load(os.path.join(D, IMG_BUNDLE), D)
    done = []
    copies = {}
    for name, (bundle, src_name) in IMAGE_COPIES.items():
        senv = ttg.load(os.path.join(D, bundle), D)
        src = next(o.read() for o in senv.objects if o.type.name == 'Texture2D' and o.read().m_Name == src_name)
        copies[name] = src
    for o in env.objects:
        if o.type.name != 'Texture2D':
            continue
        t = o.read()
        if t.m_Name in copies:
            src = copies[t.m_Name]
            assert (src.m_Width, src.m_Height, src.m_TextureFormat, src.m_MipCount) == \
                   (t.m_Width, t.m_Height, t.m_TextureFormat, t.m_MipCount), t.m_Name
            raw = bytes(src.get_image_data())
            t.image_data = raw
            t.m_CompleteImageSize = len(raw)
            t.m_StreamData.offset, t.m_StreamData.size, t.m_StreamData.path = 0, 0, ''
            t.save()
            done.append(t.m_Name)
            continue
        if t.m_Name not in IMAGES:
            continue
        im = Image.open(os.path.join(IMG_DIR, t.m_Name + '.png')).convert('RGBA')
        assert im.size == (t.m_Width, t.m_Height), t.m_Name
        t.set_image(im)          # 沿用原格式（DXT5），資料改成內嵌、不再指向 .resS
        t.save()
        done.append(t.m_Name)
    assert sorted(done) == sorted(IMAGES + list(IMAGE_COPIES)), done
    open(out_path(IMG_BUNDLE), 'wb').write(env.file.save(packer='original'))
    print('images done', done)


def port_catalog():
    b = bytearray(open(os.path.join(D, CATALOG), 'rb').read())
    # record layout: ... crc u32, size u32, 0x726, 0x767 ; zero CRC of the two rewritten bundles
    tail = bytes.fromhex('2607000067070000')
    for size in (os.path.getsize(os.path.join(D, b)) for b in (LOC_BUNDLE, STR_BUNDLE, IMG_BUNDLE)):
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
port_images()
port_resources()
for rel in MAC_ORIG:
    print(sha(os.path.join(OUT, rel)), rel)
