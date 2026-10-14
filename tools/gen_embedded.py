"""Generate Sources/Embedded.swift: small-file bsdiff patches, hashes and object templates.

usage: gen_embedded.py <orig Data dir> <patched Data dir> <templates.json> <out.swift>
"""
import base64, hashlib, json, os, subprocess, sys, tempfile

ORIG, NEW, TPL, OUT = sys.argv[1:5]
SMALL = [
    'Managed/Assembly-CSharp.dll',
    'StreamingAssets/aa/catalog.bin',
    'StreamingAssets/aa/StandaloneOSX/localization-locales_assets_all.bundle',
    'StreamingAssets/aa/StandaloneOSX/localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle',
    'StreamingAssets/aa/StandaloneOSX/localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle',
]
sha = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest()
q = lambda s: json.dumps(s, ensure_ascii=False)

lines = ['// 自動產生：tools/gen_embedded.py，請勿手動修改', 'import Foundation', '',
         'let smallPatches: [PatchFile] = [']
with tempfile.TemporaryDirectory() as td:
    for rel in SMALL:
        pf = os.path.join(td, 'p')
        subprocess.run(['bsdiff', os.path.join(ORIG, rel), os.path.join(NEW, rel), pf], check=True)
        b = base64.b64encode(open(pf, 'rb').read()).decode()
        lines.append(f'    PatchFile(rel: {q(rel)}, orig: "{sha(os.path.join(ORIG, rel))}", '
                     f'new: "{sha(os.path.join(NEW, rel))}", patch: "{b}"),')
lines.append(']')
lines.append(f'let resourcesOrigSHA = "{sha(os.path.join(ORIG, "resources.assets"))}"')

t = json.load(open(TPL))
lines.append(f'let resLayout = ResLayout(dataOffset: {t["dataOffset"]}, tableOffset: {t["tableOffset"]}, '
             f'entryCount: {t["entryCount"]}, fileSizeOffset: {t["fileSizeOffset"]})')
lines.append('let fontTemplates: [FontTemplate] = [')
for f in t['fonts']:
    lines.append('    FontTemplate(' + ', '.join([
        f'fontPathID: {f["fontPathID"]}', f'fontAssetPathID: {f["fontAssetPathID"]}',
        f'fontHead: "{f["fontHead"]}"', f'lineSpacingOffset: {f["lineSpacingOffset"]}',
        f'defaultStyle: "{f["defaultStyle"]}"', f'fontRest: "{f["fontRest"]}"', f'fontSize: {f["fontSize"]}',
        f'assetPrefix: "{f["assetPrefix"]}"', f'assetSuffix: "{f["assetSuffix"]}"',
        f'faceNumbers: "{f["faceNumbers"]}"']) + '),')
lines.append(']')
open(OUT, 'w').write('\n'.join(lines) + '\n')
print('wrote', OUT, os.path.getsize(OUT), 'bytes')
