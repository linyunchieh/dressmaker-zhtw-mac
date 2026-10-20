"""Generate Sources/Embedded.swift: bundle bsdiff patches, hashes and object templates.

usage: gen_embedded.py <orig Data dir> <patched Data dir> <templates.json> <out.swift>

DLL、catalog.bin、resources.assets 不再用 bsdiff＋整檔 hash：安裝程式會在玩家的 Mac 上直接找
IL／catalog 記錄／字型物件來改，所以遊戲 hotfix 只要沒動到這幾處就能照常安裝。
"""
import base64, hashlib, json, os, struct, subprocess, sys, tempfile

ORIG, NEW, TPL, OUT = sys.argv[1:5]
AA = 'StreamingAssets/aa/StandaloneOSX/'
BUNDLES = [
    AA + 'localization-locales_assets_all.bundle',
    AA + 'localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle',
    AA + 'localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle',
]
# 舊版補丁寫出來的 bundle（install 時若備份裡是目前的原檔，就直接從備份升級）
LEGACY = {
    BUNDLES[0]: ['12f7a20b43e62377c6f85263843e89b723127d0168a8852d930b98de785167d1'],
    BUNDLES[1]: ['7b922e80c4948a9509af5e86592ffa8126de8b0b1366ed4518d737f60d6e7374',
                 'e583ec35594123d9080407148ee9d609a5662557ca4d052f7c616bc5ad8c06b6',
                 '43fcb4648477f98d56e812315736f447f786e333390547770584f278b931a253',
                 '551e1fce38202d609f49f93970d911ced318f87ded0589d1e056243f30ed635e',  # 2.2.0
                 '52a79e7440de4fff3a0834c74f45fbce470caaeb8e7b1076636f5537f1b4bbef',  # 2.3.0
                 '91c93abefba0869b6c69110ae6c7e479cded53abea8d8b8fdc756a1e4f6493f4',  # 2.3.1
                 'bb30b508c12f88074d84f7dbcd5529fd64feca9656985a1eac49f4753fdd350f'],  # 2.3.3
    BUNDLES[2]: ['e5df96cbb6f849e54b3f55fb8f075d174d71620283534a389967d68dff91e83c',
                 '085b3690b53c6aa6edc733664c30c9419d719b6a15b2aa612ebd7e9bf148deb3'],
}
sha = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest()
q = lambda s: json.dumps(s, ensure_ascii=False)
B64 = lambda b: base64.b64encode(b).decode()

lines = ['// 自動產生：tools/gen_embedded.py，請勿手動修改', 'import Foundation', '',
         'let bundlePatches: [PatchFile] = [']
with tempfile.TemporaryDirectory() as td:
    for rel in BUNDLES:
        pf = os.path.join(td, 'p')
        subprocess.run(['bsdiff', os.path.join(ORIG, rel), os.path.join(NEW, rel), pf], check=True)
        lines.append(f'    PatchFile(rel: {q(rel)}, orig: "{sha(os.path.join(ORIG, rel))}", '
                     f'new: "{sha(os.path.join(NEW, rel))}", patch: "{B64(open(pf, "rb").read())}"),')
lines.append(']')
legacy = {rel: sorted(set(h) - {sha(os.path.join(NEW, rel))}) for rel, h in LEGACY.items()}
lines.append('let legacyPatched: [String: Set<String>] = [')
lines += [f'    {q(rel)}: [{", ".join(q(h) for h in hs)}],' for rel, hs in legacy.items()]
lines.append(']')
# catalog.bin 裡這三個 bundle 的記錄是用原版大小找的
lines.append(f'let catalogBundleSizes: [Int] = {[os.path.getsize(os.path.join(ORIG, b)) for b in BUNDLES]}')

t = json.load(open(TPL))

# LocaleFontFallbacks：EBGaramond-Medium 的 zh-Hans 備援從明體改成黑體。
# 原版遊戲的 TagBar 標籤（EBGaramond-Medium、autosize）配上明體備援時中文完全不顯示，改黑體就正常。
LFF_PATH_ID, LFF_LATIN, SERIF, SANS = t['lff'], t['latin'], t['serif'], t['sans']
res = open(os.path.join(ORIG, 'resources.assets'), 'rb').read()
for i in range(t['entryCount']):
    o = t['tableOffset'] + 24 * i
    pid, off, size = struct.unpack_from('<qQI', res, o)
    if pid == LFF_PATH_ID:
        lff = bytearray(res[t['dataOffset'] + off:t['dataOffset'] + off + size])
        break
else:
    sys.exit('LocaleFontFallbacks not found')
assert hashlib.sha256(lff).hexdigest() == t['lffOrigSHA']
latin = lff.index(struct.pack('<iq', 0, LFF_LATIN))
zh = lff.index(b'zh-Hans\0', latin) + 8 + 4
assert struct.unpack_from('<q', lff, zh)[0] == SERIF, 'unexpected fallback layout'
struct.pack_into('<q', lff, zh, SANS)
lines.append(f'let lffPatch = ObjectPatch(name: {q(t["lffName"])}, orig: "{t["lffOrigSHA"]}", new: "{B64(bytes(lff))}")')
lines.append('let fontTemplates: [FontTemplate] = [')
for f in t['fonts']:
    lines.append('    FontTemplate(' + ', '.join([
        f'fontName: {q(f["fontName"])}', f'assetName: {q(f["assetName"])}',
        f'fontOrigSHA: "{f["fontOrigSHA"]}"', f'assetOrigSHA: "{f["assetOrigSHA"]}"',
        f'systemFont: {q(f["systemFont"])}',
        f'fontHead: "{f["fontHead"]}"', f'lineSpacingOffset: {f["lineSpacingOffset"]}',
        f'defaultStyle: "{f["defaultStyle"]}"', f'fontRest: "{f["fontRest"]}"', f'fontSize: {f["fontSize"]}',
        f'assetPrefix: "{f["assetPrefix"]}"', f'assetSuffix: "{f["assetSuffix"]}"',
        f'faceNumbers: "{f["faceNumbers"]}"']) + '),')
lines.append(']')
open(OUT, 'w').write('\n'.join(lines) + '\n')
print('wrote', OUT, os.path.getsize(OUT), 'bytes')
