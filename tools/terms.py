"""在 Windows 版譯文之上再修正的用語：大陸服裝用語 → 台灣服裝業慣用說法。

fix(text, en, key) 傳回修正後的繁中字串；en 是同一個 key 的英文原文（沒有就給空字串），
用來把只該套用在特定條目的替換限定在對的範圍（例如「裙襬」只在英文是 Skirt 的款式／部件名裡改成「裙」，對話裡真的指下襬的不動）。
"""
import re

# 全域替換（舊 → 新），依序套用；長詞要排在會吃掉它的短詞前面
TERM_FIXES = [
    ('哥特', '哥德'), ('製衣', '裁縫'),
    ('帶腳紐扣', '有腳釦'), ('紐扣', '鈕釦'),
    ('繪製紙樣', '打版'), ('紙樣', '版型'),
    ('打底衫衣身', '內搭衫身片'), ('打底衫', '內搭衫'),
    ('衣身吊帶', '肩帶'), ('吊帶', '肩帶'),
    ('後衣身育克', '上身後剪接片'), ('育克襯衫', '剪接襯衫'), ('育克夾克', '剪接夾克'),
    ('立式育克', '立式剪接'), ('育克抽褶', '剪接抽褶'), ('育克', '剪接片'),
    ('嵌線', '滾邊'), ('漸變', '漸層'), ('海軍領', '水手領'), ('中式立領', '中國領'),
    ('氣眼', '雞眼'), ('波點', '點點'), ('燈芯絨', '燈心絨'), ('晚裝', '晚禮服'),
    ('工裝裙', '工作裙'), ('工裝', '工作服'),
    ('連衣裙', '洋裝'), ('裙裝', '洋裝'), ('尺碼', '尺寸'),
    ('羊毛呢', '毛呢'), ('粗花呢', '斜紋軟呢'), ('農婦袖', '農家袖'), ('蕩領', '垂墜領'),
    ('波萊羅', '波蕾若'), ('搭扣', '扣環'), ('西蘭苔', '青花筍'),
    ('小羊羔', '小羔羊'),  # 薇薇安對玩家的稱呼（lamb）
]
# Bodice：衣身 → 上身；部件名的方位改成「上身前片／後片」
BODICE_RE = [
    (re.compile(r'^上([前後])衣身'), r'上身\1上片'),
    (re.compile(r'^側([前後])衣身'), r'上身側\1片'),
    (re.compile(r'^前胸衣身'), '上身前胸片'),
    (re.compile(r'^([前後])衣身'), r'上身\1片'),
]
# Skirt：台灣的「裙襬」是下襬，款式名改成「X 裙」、部件名改成「裙片／裙身」
SKIRT_EXACT = {'裙襬': '裙子', '裙襬底邊': '裙襬', '裙襬腰頭': '裙腰頭', '全圓裙襬': '圓裙', '傘式裙襬': '傘裙'}
SKIRT_RE = [
    (re.compile(r'([上下])裙襬褶邊'), r'裙身\1層褶邊'),
    (re.compile(r'([前後左右層])裙襬'), r'\1裙片'),
    (re.compile(r'^裙襬'), '裙身'),
    (re.compile(r'裙?裙襬'), '裙'),
]
# 「一條連衣裙／晚裝」→「一件洋裝／晚禮服」
DRESS_MEASURE = re.compile(r'([一這那每])條(?=[^，。！？；…\n]{0,15}(?:洋裝|晚禮服|工作服))')
# 單條修正：(表名, id) -> 修正前的字串（套用全域替換之前）
OVERRIDES = {
    ('Content_zh-Hans', 22892765491597339): '黑色棋盤格鑲邊',  # Black Gingham Trim，原譯誤作「藍色」
    ('Content_zh-Hans', 22892765508374532): '蓋袖',            # Cap Sleeve，原譯「短袖」和 Short Sleeve 重複
}
DOUBLED = re.compile(r'裙裙|洋裝裙|上身身|片片|鈕釦釦')


def fix(text, en='', key=None):
    orig = text
    text = OVERRIDES.get(key, text)
    for old, new in TERM_FIXES:
        text = text.replace(old, new)
    if re.search('洋裝|晚禮服|工作服', text):
        text = DRESS_MEASURE.sub(r'\1件', text)
    if '衣身' in text:
        for rx, rep in BODICE_RE:
            text = rx.sub(rep, text)
        text = text.replace('衣身', '上身')
    if '裙襬' in text and 'Skirt' in en:
        if text in SKIRT_EXACT:
            text = SKIRT_EXACT[text]
        else:
            for rx, rep in SKIRT_RE:
                text = rx.sub(rep, text)
    if 'Gingham' in en:
        text = text.replace('棋盤格', '格子')
    if text != orig and (DOUBLED.search(text) or not text.strip()):
        raise ValueError(f'用語修正產生可疑字串：{key} {text!r}')
    return text
