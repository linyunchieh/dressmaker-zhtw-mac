"""依名稱找 resources.assets 裡用到的物件 pathID（遊戲更新後 pathID 會整批位移）。"""
import struct

# 遊戲字型名稱 → 換成的 Mac 系統字型（PostScript 名稱）
SYSTEM_FONTS = {
    'SourceHanSansSC-Regular': 'PingFangTC-Regular',
    'SourceHanSerifSC-Regular': 'STSongti-TC-Regular',
}


def obj_name(o):
    if o.type.name == 'MonoBehaviour':  # m_GameObject(12) m_Enabled(4) m_Script(12) m_Name
        r = o.get_raw_data()
        n = struct.unpack_from('<i', r, 28)[0]
        return r[32:32 + n].decode()
    return o.peek_name()


def find(f, type_name, name):
    hits = [pid for pid, o in f.objects.items() if o.type.name == type_name and obj_name(o) == name]
    assert len(hits) == 1, f'{type_name} {name}: {hits}'
    return hits[0]


def resource_ids(f):
    """f: UnityPy SerializedFile of resources.assets"""
    fonts = {}  # Font pathID -> (TMP_FontAsset pathID, 系統字型)
    for name, ps in SYSTEM_FONTS.items():
        fonts[find(f, 'Font', name)] = (find(f, 'MonoBehaviour', name + ' SDF'), ps)
    return {
        'fonts': fonts,
        'sans': find(f, 'MonoBehaviour', 'SourceHanSansSC-Regular SDF'),
        'serif': find(f, 'MonoBehaviour', 'SourceHanSerifSC-Regular SDF'),
        'lff': find(f, 'MonoBehaviour', 'LocaleFontFallbacks'),
        'latin': find(f, 'MonoBehaviour', 'EBGaramond-Medium SDF'),
    }
