// Dressmaker 繁體中文化補丁（macOS / Apple Silicon）
// 用法：
//   直接雙擊 app            → 對話框模式
//   zhtw-patcher install   [--game <資料夾>]
//   zhtw-patcher restore   [--game <資料夾>]
//   zhtw-patcher check     [--game <資料夾>]   只檢查能不能安裝，不寫入任何檔案
//
// 遊戲 hotfix 通常只改程式（DLL）或重新打包 resources.assets，所以除了三個翻譯 bundle 以外，
// 其他檔案都不比對整檔 hash：直接在玩家的檔案裡找要改的 IL、catalog 記錄、字型物件，
// 只核對這幾處本身有沒有變。
import AppKit
import CoreText
import CryptoKit
import Foundation

struct PatchFile { let rel: String; let orig: String; let new: String; let patch: String }
/// resources.assets 裡依名稱找的物件：原版內容的 hash → 換成的內容（base64）
struct ObjectPatch { let name: String; let orig: String; let new: String }
struct FontTemplate {
    /// Font 和 TMP_FontAsset 的物件名稱，以及原版物件內容的 hash
    let fontName: String; let assetName: String
    let fontOrigSHA: String; let assetOrigSHA: String
    /// 換成的 Mac 內建系統字型（PostScript 名稱）
    let systemFont: String
    let fontHead: String; let lineSpacingOffset: Int
    let defaultStyle: String; let fontRest: String; let fontSize: Double
    let assetPrefix: String; let assetSuffix: String; let faceNumbers: String
}

let title = "Dressmaker 繁體中文化補丁"
let resRel = "resources.assets"
let dllRel = "Managed/Assembly-CSharp.dll"
let catalogRel = "StreamingAssets/aa/catalog.bin"
let backupDirName = "_zhTW_backup"
let markerName = "installed.json"
let markerVersion = 3  // 2：加上 LocaleFontFallbacks 修正；3：每個檔案記錄原檔／補丁後 hash

struct PatchError: Error { let message: String }

// MARK: - 介面（命令列 / 對話框）

protocol UI {
    func info(_ s: String)
    func fail(_ s: String) -> Never
    func progress(_ s: String)
}

struct CLI: UI {
    func info(_ s: String) { print(s) }
    func fail(_ s: String) -> Never { FileHandle.standardError.write(("錯誤：" + s + "\n").data(using: .utf8)!); exit(1) }
    func progress(_ s: String) { print("・" + s) }
}

struct GUI: UI {
    func alert(_ s: String, _ style: NSAlert.Style) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = s
        a.alertStyle = style
        a.runModal()
    }
    func info(_ s: String) { alert(s, .informational) }
    func fail(_ s: String) -> Never { alert(s, .critical); exit(1) }
    func progress(_ s: String) {}
}

// MARK: - 小工具

func sha256(_ url: URL) -> String? {
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    var hasher = SHA256()
    while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

func b64(_ s: String) -> Data { Data(base64Encoded: s)! }

extension Data {
    mutating func le<T: FixedWidthInteger>(_ v: T) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func f32(_ v: Double) { le(Float(v).bitPattern) }
    mutating func ustr(_ s: String) {
        let b = Data(s.utf8)
        le(Int32(b.count)); append(b)
        append(Data(count: (4 - b.count % 4) % 4))
    }
    func u16be(_ o: Int) -> UInt16 { UInt16(self[startIndex + o]) << 8 | UInt16(self[startIndex + o + 1]) }
    func i16be(_ o: Int) -> Int16 { Int16(bitPattern: u16be(o)) }
    func u64be(_ o: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(self[startIndex + o + $1]) } }
    /// pattern 裡的 nil 是萬用字元；回傳所有符合的位置
    func find(_ pattern: [UInt8?]) -> [Int] {
        withUnsafeBytes { (p: UnsafeRawBufferPointer) -> [Int] in
            guard p.count >= pattern.count, let first = pattern[0] else { return [] }
            var hits: [Int] = []
            var i = 0
            while i <= p.count - pattern.count {
                if p[i] == first, pattern.indices.allSatisfy({ pattern[$0] == nil || p[i + $0] == pattern[$0] }) { hits.append(i) }
                i += 1
            }
            return hits
        }
    }
    func leInt<T: FixedWidthInteger>(_ o: Int, as: T.Type) -> T {
        var v: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) { copyBytes(to: $0, from: (startIndex + o)..<(startIndex + o + MemoryLayout<T>.size)) }
        return T(littleEndian: v)
    }
}

func isAppManagementDenied(_ e: Error) -> Bool {
    let ns = e as NSError
    let codes = [Int(EPERM), Int(EACCES)]
    if ns.domain == NSPOSIXErrorDomain, codes.contains(ns.code) { return true }
    if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteNoPermissionError { return true }
    if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError { return isAppManagementDenied(u) }
    return false
}

let appManagementHelp = """
macOS 拒絕修改遊戲檔案（「App 管理」權限）。

請到「系統設定 → 隱私權與安全性 → App 管理」，打開「\(CommandLine.arguments.count > 1 ? "終端機" : "Dressmaker繁中補丁")」的開關，再重新執行一次。
"""

// MARK: - 找遊戲

func findGame() -> URL? {
    let fm = FileManager.default
    let steam = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
    var libs = [steam]
    if let vdf = try? String(contentsOf: steam.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8) {
        let re = try! NSRegularExpression(pattern: #""path"\s+"([^"]+)""#)
        for m in re.matches(in: vdf, range: NSRange(vdf.startIndex..., in: vdf)) {
            if let r = Range(m.range(at: 1), in: vdf) { libs.append(URL(fileURLWithPath: String(vdf[r]).replacingOccurrences(of: "\\\\", with: "\\"))) }
        }
    }
    for lib in libs {
        let g = lib.appendingPathComponent("steamapps/common/Dressmaker")
        if fm.fileExists(atPath: g.appendingPathComponent("Dressmaker.app/Contents/Resources/Data").path) { return g }
    }
    return nil
}

func gameRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains {
        $0.executableURL?.lastPathComponent == "Dressmaker" || $0.bundleURL?.lastPathComponent == "Dressmaker.app"
    }
}

// MARK: - 系統字型

struct SystemFont {
    let family: String, style: String
    let data: Data
    let upem: Int, ascent: Int, descent: Int, lineGap: Int
    let underlinePos: Int, underlineThickness: Int
    let capTop: Double, xTop: Double
}

func loadSystemFont(_ psName: String) throws -> SystemFont {
    let probe = CTFontCreateWithName(psName as CFString, 12, nil)
    guard (CTFontCopyPostScriptName(probe) as String) == psName else {
        throw PatchError(message: "這台 Mac 找不到系統字型 \(psName)。\n請打開「字體簿」搜尋並下載後再試。")
    }
    func table(_ tag: String) -> Data? {
        let t = tag.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return CTFontCopyTable(probe, t, CTFontTableOptions(rawValue: 0)) as Data?
    }
    // 依 CoreText 提供的表格重組成單一字型檔（TTC 拆單一字重）
    guard let tagsArr = CTFontCopyAvailableTables(probe, CTFontTableOptions(rawValue: 0)) else {
        throw PatchError(message: "無法讀取字型 \(psName)")
    }
    var tables: [(UInt32, Data)] = []
    for i in 0..<CFArrayGetCount(tagsArr) {
        let tag = UInt32(UInt(bitPattern: CFArrayGetValueAtIndex(tagsArr, i)))
        if let d = CTFontCopyTable(probe, tag, CTFontTableOptions(rawValue: 0)) as Data? { tables.append((tag, d)) }
    }
    tables.sort { $0.0 < $1.0 }
    let isCFF = tables.contains { $0.0 == 0x4346_4620 }  // 'CFF '
    var sfnt = Data()
    func be32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { sfnt.append(contentsOf: $0) } }
    func be16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { sfnt.append(contentsOf: $0) } }
    let n = UInt16(tables.count)
    var pow2: UInt16 = 1, log2: UInt16 = 0
    while pow2 * 2 <= n { pow2 *= 2; log2 += 1 }
    be32(isCFF ? 0x4F54_544F : 0x0001_0000); be16(n); be16(pow2 * 16); be16(log2); be16(n * 16 - pow2 * 16)
    var offset = 12 + 16 * tables.count
    for (tag, d) in tables {
        var sum: UInt32 = 0
        var padded = d; padded.append(Data(count: (4 - d.count % 4) % 4))
        padded.withUnsafeBytes { p in
            for k in stride(from: 0, to: padded.count, by: 4) { sum &+= p.loadUnaligned(fromByteOffset: k, as: UInt32.self).bigEndian }
        }
        be32(tag); be32(sum); be32(UInt32(offset)); be32(UInt32(d.count))
        offset += padded.count
    }
    for (_, d) in tables { sfnt.append(d); sfnt.append(Data(count: (4 - d.count % 4) % 4)) }

    guard let head = table("head"), let hhea = table("hhea"), let post = table("post") else {
        throw PatchError(message: "字型 \(psName) 缺少必要表格")
    }
    let upem = Int(head.u16be(18))
    let big = CTFontCreateWithName(psName as CFString, CGFloat(upem), nil)
    func top(_ ch: String) -> Double {
        var u = Array(ch.utf16), g = [CGGlyph](repeating: 0, count: u.count)
        CTFontGetGlyphsForCharacters(big, &u, &g, u.count)
        var r = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(big, .horizontal, &g, &r, 1)
        return Double(r.maxY)
    }
    let style = (CTFontCopyName(probe, kCTFontStyleNameKey) as String?) ?? "Regular"
    return SystemFont(family: CTFontCopyFamilyName(probe) as String, style: style, data: sfnt, upem: upem,
                      ascent: Int(hhea.i16be(4)), descent: Int(hhea.i16be(6)), lineGap: Int(hhea.i16be(8)),
                      underlinePos: Int(post.i16be(8)), underlineThickness: Int(post.i16be(10)),
                      capTop: top("H"), xTop: top("x"))
}

// MARK: - 物件重建

func buildFontObject(_ t: FontTemplate, _ f: SystemFont) -> Data {
    let scale = t.fontSize / Double(f.upem)
    var head = b64(t.fontHead)
    var ls = Data(); ls.f32(Double(f.ascent - f.descent + f.lineGap) * scale)
    head.replaceSubrange(t.lineSpacingOffset..<(t.lineSpacingOffset + 4), with: ls)
    var d = head
    d.le(Int32(f.data.count)); d.append(f.data); d.append(Data(count: (4 - f.data.count % 4) % 4))
    d.f32(Double(f.ascent) * scale); d.f32(Double(f.descent) * scale)
    d.append(b64(t.defaultStyle))
    d.le(Int32(1)); d.ustr(f.family)
    d.append(b64(t.fontRest))
    return d
}

func buildFontAsset(_ t: FontTemplate, _ f: SystemFont) -> Data {
    let nums = b64(t.faceNumbers)
    var v = (0..<18).map { Double(Float(bitPattern: nums.leInt($0 * 4, as: UInt32.self))) }
    let s = v[0] / Double(f.upem)  // m_PointSize / UnitsPerEM
    v[3] = Double(f.ascent - f.descent + f.lineGap) * s     // LineHeight
    v[4] = Double(f.ascent) * s                              // AscentLine
    v[5] = (f.capTop * s).rounded(.toNearestOrEven)          // CapLine
    v[6] = (f.xTop * s).rounded(.toNearestOrEven)            // MeanLine
    v[8] = Double(f.descent) * s                             // DescentLine
    v[9] = v[4]; v[11] = v[8]                                // Super/SubscriptOffset
    v[13] = Double(f.underlinePos) * s; v[14] = Double(f.underlineThickness) * s
    var d = b64(t.assetPrefix)
    d.ustr(f.family); d.ustr(f.style)
    for (i, x) in v.enumerated() {
        if i == 2 { d.le(Int32(f.upem)) } else { d.f32(x) }
    }
    d.append(b64(t.assetSuffix))
    return d
}

// MARK: - resources.assets（SerializedFile v22，沒有 typetree）

struct AssetObject { let index: Int; let pathID: Int64; let start: Int; let size: Int; let classID: Int32 }

/// 只讀表頭、型別表和物件表；pathID、物件表位置每次遊戲更新都可能不同，所以每次都重新解析。
struct AssetsFile {
    static let fileSizeOffset = 0x18
    let data: Data
    let dataOffset: Int, tableOffset: Int
    let objects: [AssetObject]

    init(_ url: URL) throws {
        func bad(_ s: String) -> PatchError { PatchError(message: "resources.assets 的格式認不得（\(s)）") }
        data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count > 0x40, data.leInt(8, as: UInt32.self).bigEndian == 22, data[0x10] == 0 else { throw bad("版本") }
        guard Int(data.u64be(AssetsFile.fileSizeOffset)) == data.count else { throw bad("檔案大小") }
        dataOffset = Int(data.u64be(0x20))
        guard let z = data[0x30...].firstIndex(of: 0) else { throw bad("Unity 版本") }
        var p = z + 1 + 4                                   // Unity 版本字串、target platform
        guard data[p] == 0 else { throw bad("typetree") }   // enableTypeTree
        p += 1
        let typeCount = Int(data.leInt(p, as: Int32.self)); p += 4
        guard (1...10000).contains(typeCount) else { throw bad("型別數") }
        var classIDs: [Int32] = []
        for _ in 0..<typeCount {
            let cid = data.leInt(p, as: Int32.self)
            let scriptID = cid == 114 ? 16 : 0
            p += 4 + 1 + 2 + scriptID + 16                  // classID, stripped, scriptTypeIndex, scriptID, typeHash
            classIDs.append(cid)
        }
        let count = Int(data.leInt(p, as: Int32.self)); p += 4
        p = (p + 3) & ~3
        tableOffset = p
        guard count > 0, p + 24 * count <= dataOffset else { throw bad("物件表") }
        var objs: [AssetObject] = []
        for i in 0..<count {
            let o = p + 24 * i
            let t = Int(data.leInt(o + 20, as: Int32.self))
            let start = Int(data.leInt(o + 8, as: UInt64.self)) + dataOffset, size = Int(data.leInt(o + 16, as: UInt32.self))
            guard classIDs.indices.contains(t), start + size <= data.count else { throw bad("物件 \(i)") }
            objs.append(AssetObject(index: i, pathID: data.leInt(o, as: Int64.self), start: start, size: size, classID: classIDs[t]))
        }
        objects = objs
    }

    func bytes(_ o: AssetObject) -> Data { data.subdata(in: o.start..<(o.start + o.size)) }

    /// Font 的 m_Name 在最前面；MonoBehaviour 前面是 m_GameObject(12) m_Enabled(4) m_Script(12)
    func name(_ o: AssetObject) -> String? {
        guard let off = [128: 0, 114: 28][o.classID], o.size >= off + 4 else { return nil }
        let n = Int(data.leInt(o.start + off, as: Int32.self))
        guard (0...256).contains(n), off + 4 + n <= o.size else { return nil }
        return String(data: data.subdata(in: (o.start + off + 4)..<(o.start + off + 4 + n)), encoding: .utf8)
    }

    func find(classID: Int32, name want: String) -> AssetObject? {
        let hits = objects.filter { $0.classID == classID && name($0) == want }
        return hits.count == 1 ? hits[0] : nil
    }
}

/// 補丁要換掉的物件；原版內容和製作補丁時不同就回傳錯誤說明。
func resourceTargets(_ f: AssetsFile) -> (fonts: [(FontTemplate, AssetObject, AssetObject)], lff: AssetObject?, problem: String?) {
    var fonts: [(FontTemplate, AssetObject, AssetObject)] = []
    var problem: String?
    for t in fontTemplates {
        guard let fo = f.find(classID: 128, name: t.fontName), let fa = f.find(classID: 114, name: t.assetName) else {
            problem = problem ?? "找不到字型物件 \(t.fontName)"; continue
        }
        if sha256(f.bytes(fo)) != t.fontOrigSHA { problem = problem ?? "字型 \(t.fontName) 已經變更" }
        if sha256(f.bytes(fa)) != t.assetOrigSHA { problem = problem ?? "字型設定 \(t.assetName) 已經變更" }
        fonts.append((t, fo, fa))
    }
    let lff = f.find(classID: 114, name: lffPatch.name)
    if lff == nil { problem = problem ?? "找不到 \(lffPatch.name)" }
    return (fonts, lff, problem)
}

/// 依原檔重寫 resources.assets：替換指定物件，其餘物件依 16 byte 對齊重新排列。
func rewriteResources(src f: AssetsFile, dst: URL, replace: [Int64: Data]) throws {
    var meta = f.data.subdata(in: 0..<f.dataOffset)
    guard Set(replace.keys).isSubset(of: Set(f.objects.map(\.pathID))) else { throw PatchError(message: "物件表不符") }
    FileManager.default.createFile(atPath: dst.path, contents: nil)
    let out = try FileHandle(forWritingTo: dst)
    defer { try? out.close() }
    try out.seek(toOffset: UInt64(f.dataOffset))
    var pos = f.dataOffset
    for e in f.objects.sorted(by: { $0.start < $1.start }) {
        let pad = (16 - pos % 16) % 16
        if pad > 0 { try out.write(contentsOf: Data(count: pad)); pos += pad }
        let body = replace[e.pathID] ?? f.bytes(e)
        let o = f.tableOffset + 24 * e.index
        var rel = Data(); rel.le(UInt64(pos - f.dataOffset)); rel.le(UInt32(body.count))
        meta.replaceSubrange((o + 8)..<(o + 20), with: rel)
        try out.write(contentsOf: body)
        pos += body.count
    }
    withUnsafeBytes(of: UInt64(pos).bigEndian) { meta.replaceSubrange(AssetsFile.fileSizeOffset..<(AssetsFile.fileSizeOffset + 8), with: $0) }
    try out.seek(toOffset: 0)
    try out.write(contentsOf: meta)
}

/// 寫完後重新解析，確認替換的物件內容正確、未替換物件內容未變
func verifyResources(_ url: URL, orig o: AssetsFile, replace: [Int64: Data]) -> Bool {
    guard let d = try? AssetsFile(url), d.objects.count == o.objects.count, d.tableOffset == o.tableOffset else { return false }
    for (a, b) in zip(d.objects, o.objects) {
        guard a.pathID == b.pathID, a.classID == b.classID, a.start % 16 == 0 else { return false }
        if let r = replace[a.pathID] {
            guard d.bytes(a) == r else { return false }
        } else if a.index % 97 == 0 || a.size != b.size {  // 抽樣比對未替換物件
            guard d.bytes(a) == o.bytes(b) else { return false }
        }
    }
    return true
}

// MARK: - 各檔案的狀態判斷與套用

enum FileState: Equatable { case original, patched, unknown(String) }

/// LanguageSelectorPopup.NativeName：brtrue.s 7 → pop; nop（一律回傳 locale.LocaleName）
/// ldarg.0 callvirt stloc.1 ldloca.s 1 call stloc.0 ldloc.0 [brtrue.s 7] ...（metadata token 每版不同，用萬用字元）
let ilPattern: [UInt8?] = [0x02, 0x6f, nil, nil, nil, 0x0a, 0x0b, 0x12, 0x01, 0x28, nil, nil, nil, 0x0a, 0x0a, 0x06,
                           nil, nil, 0x02, 0x6f, nil, nil, nil, 0x0a, 0x2a, 0x06, 0x6f, nil, nil, nil, 0x0a, 0x2a]
let ilPatchOffset = 16

func dllState(_ d: Data) -> (FileState, Int?) {
    let hits = d.find(ilPattern)
    guard hits.count == 1 else { return (.unknown("找不到要修改的程式碼（符合 \(hits.count) 處）"), nil) }
    let i = hits[0] + ilPatchOffset
    switch (d[i], d[i + 1]) {
    case (0x2d, 0x07): return (.original, i)
    case (0x26, 0x00): return (.patched, i)
    default: return (.unknown("要修改的程式碼內容不同"), nil)
    }
}

/// catalog.bin 裡三個 bundle 的記錄：... crc u32, size u32, 0x726, 0x767；CRC 清成 0 才能載入改過的 bundle
func catalogCRCOffsets(_ d: Data) -> [Int]? {
    var offs: [Int] = []
    for size in catalogBundleSizes {
        var pat = Data(); pat.le(UInt32(size)); pat.append(contentsOf: [0x26, 0x07, 0, 0, 0x67, 0x07, 0, 0])
        let hits = d.find(pat.map { Optional($0) })
        guard hits.count == 1, hits[0] >= 4 else { return nil }
        offs.append(hits[0] - 4)
    }
    return offs
}

func catalogState(_ d: Data) -> FileState {
    guard let offs = catalogCRCOffsets(d) else { return .unknown("找不到翻譯檔的記錄") }
    return offs.allSatisfy { d.leInt($0, as: UInt32.self) == 0 } ? .patched : .original
}

func resourcesState(_ url: URL) -> FileState {
    let f: AssetsFile
    do { f = try AssetsFile(url) } catch let e as PatchError { return .unknown(e.message) } catch { return .unknown("\(error)") }
    let t = resourceTargets(f)
    if let lff = t.lff, f.bytes(lff) == b64(lffPatch.new) { return .patched }
    if let p = t.problem { return .unknown(p) }
    if sha256(f.bytes(t.lff!)) != lffPatch.orig { return .unknown("\(lffPatch.name) 已經變更") }
    return .original
}

struct Target {
    let rel: String
    let state: (URL) -> FileState
    /// 從 source 產生補丁後的檔案寫到 dst（寫完要自己驗證）
    let apply: (URL, URL) throws -> Void
}

func fileState(_ url: URL, _ read: (Data) -> FileState) -> FileState {
    guard let d = try? Data(contentsOf: url, options: .alwaysMapped) else { return .unknown("讀不到檔案") }
    return read(d)
}

func makeTargets(fonts: @escaping () throws -> [String: SystemFont]) -> [Target] {
    var ts: [Target] = []
    for p in bundlePatches {
        ts.append(Target(rel: p.rel, state: { u in
            switch sha256(u) {
            case p.new?: return .patched
            case p.orig?: return .original
            default: return .unknown("翻譯檔和補丁製作時的版本不同（遊戲更新了文字或圖片）")
            }
        }, apply: { src, dst in
            let pf = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try b64(p.patch).write(to: pf)
            defer { try? FileManager.default.removeItem(at: pf) }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/bspatch")
            proc.arguments = [src.path, dst.path, pf.path]
            try proc.run(); proc.waitUntilExit()
            guard proc.terminationStatus == 0, sha256(dst) == p.new else { throw PatchError(message: "\(p.rel) 寫入後驗證失敗，已中止。") }
        }))
    }
    ts.append(Target(rel: dllRel, state: { fileState($0) { dllState($0).0 } }, apply: { src, dst in
        var d = try Data(contentsOf: src)
        guard case (.original, let i?) = dllState(d) else { throw PatchError(message: "\(dllRel) 內容不符，已中止。") }
        d.replaceSubrange(i..<(i + 2), with: [0x26, 0x00])
        try d.write(to: dst)
        guard let w = try? Data(contentsOf: dst), w == d, dllState(w).0 == .patched else { throw PatchError(message: "\(dllRel) 寫入後驗證失敗，已中止。") }
    }))
    ts.append(Target(rel: catalogRel, state: { fileState($0, catalogState) }, apply: { src, dst in
        var d = try Data(contentsOf: src)
        guard let offs = catalogCRCOffsets(d) else { throw PatchError(message: "\(catalogRel) 內容不符，已中止。") }
        for o in offs { d.replaceSubrange(o..<(o + 4), with: Data(count: 4)) }
        try d.write(to: dst)
        guard let w = try? Data(contentsOf: dst), w == d, catalogState(w) == .patched else { throw PatchError(message: "\(catalogRel) 寫入後驗證失敗，已中止。") }
    }))
    ts.append(Target(rel: resRel, state: resourcesState, apply: { src, dst in
        let f = try AssetsFile(src)
        let t = resourceTargets(f)
        guard t.problem == nil, let lff = t.lff else { throw PatchError(message: "resources.assets 內容不符，已中止。") }
        let sys = try fonts()
        var replace: [Int64: Data] = [lff.pathID: b64(lffPatch.new)]
        for (tpl, fo, fa) in t.fonts {
            replace[fo.pathID] = buildFontObject(tpl, sys[tpl.systemFont]!)
            replace[fa.pathID] = buildFontAsset(tpl, sys[tpl.systemFont]!)
        }
        try rewriteResources(src: f, dst: dst, replace: replace)
        guard verifyResources(dst, orig: f, replace: replace) else { throw PatchError(message: "resources.assets 驗證失敗，已中止。") }
    }))
    return ts
}

enum Action { case done, apply(source: URL, fromBackup: Bool), fail(String) }

struct Layout {
    let data: URL, backup: URL, marker: URL
    init(_ game: URL) {
        data = game.appendingPathComponent("Dressmaker.app/Contents/Resources/Data")
        backup = game.appendingPathComponent(backupDirName)
        marker = backup.appendingPathComponent(markerName)
    }
    var markerInfo: [String: Any] { ((try? JSONSerialization.jsonObject(with: Data(contentsOf: marker))) as? [String: Any]) ?? [:] }
    /// 這個檔案是不是之前的補丁寫出來的（可以從備份的原檔重新套用）
    func ourEarlierOutput(_ rel: String, sha: String?) -> Bool {
        guard let sha else { return false }
        let m = markerInfo
        if let files = m["files"] as? [String: [String: String]], files[rel]?["new"] == sha { return true }
        if rel == resRel, m["resources"] as? String == sha { return true }
        return legacyPatched[rel]?.contains(sha) ?? false
    }
}

func plan(_ L: Layout, _ targets: [Target]) -> [(Target, Action)] {
    targets.map { t in
        let cur = L.data.appendingPathComponent(t.rel)
        switch t.state(cur) {
        case .patched: return (t, .done)
        case .original: return (t, .apply(source: cur, fromBackup: false))
        case .unknown(let why):
            if !FileManager.default.fileExists(atPath: cur.path) { return (t, .fail("找不到檔案")) }
            let b = L.backup.appendingPathComponent(t.rel)
            if L.ourEarlierOutput(t.rel, sha: sha256(cur)), t.state(b) == .original { return (t, .apply(source: b, fromBackup: true)) }
            return (t, .fail(why))
        }
    }
}

let mismatchHelp = """
遊戲更新動到了補丁要改的地方，這一版補丁還無法套用，請到 GitHub 下載新版。
若裝過其他補丁或改過遊戲檔案，請先在 Steam「驗證遊戲檔案完整性」後再試。
"""

func failures(_ p: [(Target, Action)]) -> [String] {
    p.compactMap { t, a in if case .fail(let why) = a { return "・\((t.rel as NSString).lastPathComponent)：\(why)" } else { return nil } }
}

// MARK: - 安裝 / 還原 / 檢查

func atomicReplace(_ target: URL, with tmp: URL) throws {
    _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
}

func loadFonts() throws -> [String: SystemFont] {
    var r: [String: SystemFont] = [:]
    for t in fontTemplates where r[t.systemFont] == nil { r[t.systemFont] = try loadSystemFont(t.systemFont) }
    return r
}

func install(game: URL, ui: UI) {
    let fm = FileManager.default
    let L = Layout(game)
    if gameRunning() { ui.fail("請先關閉遊戲再安裝。") }

    ui.progress("檢查遊戲檔案…")
    var sysFonts: [String: SystemFont]?
    let targets = makeTargets { if let f = sysFonts { return f }; sysFonts = try loadFonts(); return sysFonts! }
    let p = plan(L, targets)
    let bad = failures(p)
    if !bad.isEmpty { ui.fail("以下檔案無法套用：\n" + bad.joined(separator: "\n") + "\n\n" + mismatchHelp) }
    let todo = p.compactMap { t, a -> (Target, URL, Bool)? in if case .apply(let s, let b) = a { return (t, s, b) } else { return nil } }
    if todo.isEmpty { ui.info("已經是繁體中文化版本，不需要重複安裝。"); return }

    if todo.contains(where: { $0.0.rel == resRel }) {
        ui.progress("讀取系統字型（蘋方-繁、宋體-繁）…")
        do { sysFonts = try loadFonts() } catch let e as PatchError { ui.fail(e.message) } catch { ui.fail("\(error)") }
    }

    var files = (L.markerInfo["files"] as? [String: [String: String]]) ?? [:]
    do {
        ui.progress("備份原始檔案…")
        for (t, src, fromBackup) in todo where !fromBackup {
            let b = L.backup.appendingPathComponent(t.rel)
            if sha256(b) == sha256(src) { continue }
            try fm.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: b)
            try fm.copyItem(at: src, to: b)
        }
        for (t, src, _) in todo {
            let name = (t.rel as NSString).lastPathComponent
            ui.progress(t.rel == resRel ? "重建 resources.assets（換成蘋方-繁／宋體-繁）…" : "寫入 \(name)")
            let target = L.data.appendingPathComponent(t.rel)
            let tmp = target.appendingPathExtension("zhtw_tmp")
            try? fm.removeItem(at: tmp)
            do { try t.apply(src, tmp) } catch { try? fm.removeItem(at: tmp); throw error }
            let newSHA = sha256(tmp)!
            files[t.rel] = ["orig": sha256(src)!, "new": newSHA]
            try atomicReplace(target, with: tmp)
        }
        var m: [String: Any] = ["version": markerVersion, "files": files]
        if let f = sysFonts { m["fonts"] = fontTemplates.map { f[$0.systemFont]!.family } }
        else if let old = L.markerInfo["fonts"] { m["fonts"] = old }
        try JSONSerialization.data(withJSONObject: m, options: [.prettyPrinted, .sortedKeys]).write(to: L.marker)
    } catch let e as PatchError {
        ui.fail(e.message)
    } catch {
        ui.fail(isAppManagementDenied(error) ? appManagementHelp : "安裝失敗：\(error.localizedDescription)")
    }
    ui.info("安裝完成！\n\n進遊戲後在「選項 → 語言」選「繁體中文」。\n原始檔案已備份在：\n\(L.backup.path)\n\nSteam 更新遊戲後會蓋回原版，到時再執行一次安裝即可。")
}

func restore(game: URL, ui: UI) {
    let fm = FileManager.default
    let L = Layout(game)
    if gameRunning() { ui.fail("請先關閉遊戲再還原。") }
    var restored = 0
    do {
        for t in makeTargets(fonts: { [:] }) {
            let cur = L.data.appendingPathComponent(t.rel)
            let s = t.state(cur)
            if s == .original { continue }
            // 不認得、也不是補丁寫的檔案（例如 Steam 更新過）就不要用舊備份蓋掉
            if case .unknown = s, !L.ourEarlierOutput(t.rel, sha: sha256(cur)) { continue }
            let b = L.backup.appendingPathComponent(t.rel)
            guard t.state(b) == .original else {
                throw PatchError(message: "找不到 \(t.rel) 的有效備份。\n請改用 Steam「驗證遊戲檔案完整性」還原。")
            }
            ui.progress("還原 \((t.rel as NSString).lastPathComponent)")
            let tmp = cur.appendingPathExtension("zhtw_tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: b, to: tmp)
            try atomicReplace(cur, with: tmp)
            restored += 1
        }
        try? fm.removeItem(at: L.marker)
    } catch let e as PatchError {
        ui.fail(e.message)
    } catch {
        ui.fail(isAppManagementDenied(error) ? appManagementHelp : "還原失敗：\(error.localizedDescription)")
    }
    ui.info(restored == 0 ? "目前已經是原版檔案。" : "已還原為原版。")
}

/// 只檢查，不寫入：遊戲更新後用來判斷這一版補丁還能不能裝
func check(game: URL) -> Int32 {
    let L = Layout(game)
    var ok = true
    for (t, a) in plan(L, makeTargets(fonts: { [:] })) {
        let line: String
        switch a {
        case .done: line = "✓ 已安裝"
        case .apply(_, false): line = "✓ 原版，可以安裝"
        case .apply(_, true): line = "✓ 舊版補丁，會從備份重新套用"
        case .fail(let why): line = "✗ \(why)"; ok = false
        }
        print("\(line)　\(t.rel)")
    }
    for t in fontTemplates {
        do { _ = try loadSystemFont(t.systemFont); print("✓ 系統字型 \(t.systemFont)") }
        catch let e as PatchError { print("✗ \(e.message)"); ok = false } catch { print("✗ \(error)"); ok = false }
    }
    print(ok ? "\n可以安裝。" : "\n" + mismatchHelp)
    return ok ? 0 : 1
}

// MARK: - 進入點

func validGame(_ u: URL) -> Bool {
    FileManager.default.fileExists(atPath: u.appendingPathComponent("Dressmaker.app/Contents/Resources/Data").path)
}

let args = Array(CommandLine.arguments.dropFirst())
if let cmd = args.first, ["install", "restore", "check"].contains(cmd) {
    setvbuf(stdout, nil, _IONBF, 0)
    let ui = CLI()
    var game: URL?
    if let i = args.firstIndex(of: "--game"), i + 1 < args.count { game = URL(fileURLWithPath: args[i + 1]) }
    guard let g = game ?? findGame() else { ui.fail("找不到遊戲，請用 --game 指定含有 Dressmaker.app 的資料夾。") }
    guard validGame(g) else { ui.fail("這個資料夾裡沒有 Dressmaker.app：\(g.path)") }
    ui.info("遊戲位置：\(g.path)")
    switch cmd {
    case "install": install(game: g, ui: ui)
    case "restore": restore(game: g, ui: ui)
    default: exit(check(game: g))
    }
} else if let cmd = args.first, !cmd.hasPrefix("-psn") {
    print("用法：zhtw-patcher install|restore|check [--game <含有 Dressmaker.app 的資料夾>]")
    exit(2)
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    let ui = GUI()
    var game = findGame()
    if game == nil {
        let panel = NSOpenPanel()
        panel.message = "找不到遊戲，請選擇含有 Dressmaker.app 的資料夾"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        guard panel.runModal() == .OK, let u = panel.url else { exit(0) }
        game = u
    }
    guard let g = game, validGame(g) else { ui.fail("這個資料夾裡沒有 Dressmaker.app。") }
    let a = NSAlert()
    a.messageText = title
    a.informativeText = "將官方簡體中文換成繁體中文（台灣用語），字型使用這台 Mac 內建的蘋方-繁／宋體-繁。\n\n遊戲位置：\(g.path)"
    a.addButton(withTitle: "安裝繁體中文")
    a.addButton(withTitle: "還原原版")
    a.addButton(withTitle: "取消")
    switch a.runModal() {
    case .alertFirstButtonReturn: install(game: g, ui: ui)
    case .alertSecondButtonReturn: restore(game: g, ui: ui)
    default: break
    }
}
