// Dressmaker 繁體中文化補丁（macOS / Apple Silicon）
// 用法：
//   直接雙擊 app            → 對話框模式
//   zhtw-patcher install   [--game <資料夾>]
//   zhtw-patcher restore   [--game <資料夾>]
import AppKit
import CoreText
import CryptoKit
import Foundation

struct PatchFile { let rel: String; let orig: String; let new: String; let patch: String }
struct ResLayout { let dataOffset: Int; let tableOffset: Int; let entryCount: Int; let fileSizeOffset: Int }
struct FontTemplate {
    let fontPathID: Int64; let fontAssetPathID: Int64
    let fontHead: String; let lineSpacingOffset: Int
    let defaultStyle: String; let fontRest: String; let fontSize: Double
    let assetPrefix: String; let assetSuffix: String; let faceNumbers: String
}

let title = "Dressmaker 繁體中文化補丁"
let resRel = "resources.assets"
let backupDirName = "_zhTW_backup"
let markerName = "installed.json"
/// 遊戲字型物件 → 對方 Mac 內建的系統字型（PostScript 名稱）
let systemFonts: [Int64: String] = [4055: "PingFangTC-Regular", 4054: "STSongti-TC-Regular"]

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

/// 依原檔重寫 resources.assets：替換指定物件，其餘物件依 16 byte 對齊重新排列。
func rewriteResources(src: URL, dst: URL, replace: [Int64: Data]) throws {
    let L = resLayout
    let orig = try Data(contentsOf: src, options: .alwaysMapped)
    var meta = orig.subdata(in: 0..<L.dataOffset)
    struct Entry { let index: Int; let pid: Int64; let start: Int; let size: Int }
    var entries: [Entry] = []
    for i in 0..<L.entryCount {
        let o = L.tableOffset + 24 * i
        entries.append(Entry(index: i, pid: meta.leInt(o, as: Int64.self),
                             start: Int(meta.leInt(o + 8, as: UInt64.self)) + L.dataOffset,
                             size: Int(meta.leInt(o + 16, as: UInt32.self))))
    }
    guard Set(replace.keys).isSubset(of: Set(entries.map(\.pid))) else { throw PatchError(message: "物件表不符") }
    entries.sort { $0.start < $1.start }

    FileManager.default.createFile(atPath: dst.path, contents: nil)
    let out = try FileHandle(forWritingTo: dst)
    defer { try? out.close() }
    try out.seek(toOffset: UInt64(L.dataOffset))
    var pos = L.dataOffset
    for e in entries {
        let pad = (16 - pos % 16) % 16
        if pad > 0 { try out.write(contentsOf: Data(count: pad)); pos += pad }
        let body = replace[e.pid] ?? orig.subdata(in: e.start..<(e.start + e.size))
        let o = L.tableOffset + 24 * e.index
        var rel = Data(); rel.le(UInt64(pos - L.dataOffset)); rel.le(UInt32(body.count))
        meta.replaceSubrange((o + 8)..<(o + 20), with: rel)
        try out.write(contentsOf: body)
        pos += body.count
    }
    withUnsafeBytes(of: UInt64(pos).bigEndian) { meta.replaceSubrange(L.fileSizeOffset..<(L.fileSizeOffset + 8), with: $0) }
    try out.seek(toOffset: 0)
    try out.write(contentsOf: meta)
}

/// 寫完後重新讀物件表，確認替換的物件大小正確、未替換物件內容未變
func verifyResources(_ url: URL, orig: URL, replace: [Int64: Data]) -> Bool {
    let L = resLayout
    guard let d = try? Data(contentsOf: url, options: .alwaysMapped),
          let o = try? Data(contentsOf: orig, options: .alwaysMapped) else { return false }
    guard Int(d.subdata(in: L.fileSizeOffset..<(L.fileSizeOffset + 8)).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) == d.count else { return false }
    for i in 0..<L.entryCount {
        let p = L.tableOffset + 24 * i
        let pid = d.leInt(p, as: Int64.self)
        let start = Int(d.leInt(p + 8, as: UInt64.self)) + L.dataOffset, size = Int(d.leInt(p + 16, as: UInt32.self))
        guard start % 16 == 0, start + size <= d.count else { return false }
        if let r = replace[pid] {
            guard d.subdata(in: start..<(start + size)) == r else { return false }
        } else if i % 97 == 0 {  // 抽樣比對未替換物件
            let os = Int(o.leInt(p + 8, as: UInt64.self)) + L.dataOffset
            guard d.subdata(in: start..<(start + size)) == o.subdata(in: os..<(os + size)) else { return false }
        }
    }
    return true
}

// MARK: - 安裝 / 還原

func atomicReplace(_ target: URL, with tmp: URL) throws {
    _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
}

func install(game: URL, ui: UI) {
    let fm = FileManager.default
    let data = game.appendingPathComponent("Dressmaker.app/Contents/Resources/Data")
    let backup = game.appendingPathComponent(backupDirName)
    let marker = backup.appendingPathComponent(markerName)
    if gameRunning() { ui.fail("請先關閉遊戲再安裝。") }

    ui.progress("檢查遊戲檔案版本…")
    var todo: [PatchFile] = []
    var upgrade: Set<String> = []  // 舊版補丁裝過的檔案：改從備份的原檔重新套用
    let hasMarker = fm.fileExists(atPath: marker.path)
    for p in smallPatches {
        switch sha256(data.appendingPathComponent(p.rel)) {
        case p.new?: continue
        case p.orig?: todo.append(p)
        case nil: ui.fail("找不到檔案：\(p.rel)")
        case _ where hasMarker && sha256(backup.appendingPathComponent(p.rel)) == p.orig:
            todo.append(p); upgrade.insert(p.rel)
        default: ui.fail("檔案版本不符：\(p.rel)\n\n遊戲可能已經更新，這個補丁只適用於製作時的版本。若裝過其他補丁，請先在 Steam「驗證遊戲檔案完整性」後再試。")
        }
    }
    let resURL = data.appendingPathComponent(resRel)
    let resSHA = sha256(resURL)
    let installedSHA = (try? JSONSerialization.jsonObject(with: Data(contentsOf: marker))) .flatMap { ($0 as? [String: Any])?["resources"] as? String }
    let resTodo: Bool
    switch resSHA {
    case resourcesOrigSHA?: resTodo = true
    case installedSHA where installedSHA != nil: resTodo = false
    case nil: ui.fail("找不到檔案：\(resRel)")
    default: ui.fail("檔案版本不符：\(resRel)\n\n遊戲可能已經更新，或裝過其他補丁。請先在 Steam「驗證遊戲檔案完整性」後再試。")
    }
    if todo.isEmpty && !resTodo { ui.info("已經是繁體中文化版本，不需要重複安裝。"); return }

    var replace: [Int64: Data] = [:]
    var fontNames: [String] = []
    if resTodo {
        ui.progress("讀取系統字型（蘋方-繁、宋體-繁）…")
        for t in fontTemplates {
            do {
                let f = try loadSystemFont(systemFonts[t.fontPathID]!)
                replace[t.fontPathID] = buildFontObject(t, f)
                replace[t.fontAssetPathID] = buildFontAsset(t, f)
                fontNames.append(f.family)
            } catch let e as PatchError { ui.fail(e.message) } catch { ui.fail("\(error)") }
        }
    }

    do {
        ui.progress("備份原始檔案…")
        for rel in todo.map(\.rel) + (resTodo ? [resRel] : []) where !upgrade.contains(rel) {
            let b = backup.appendingPathComponent(rel)
            let origSHA = rel == resRel ? resourcesOrigSHA : todo.first { $0.rel == rel }!.orig
            if sha256(b) == origSHA { continue }
            try fm.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: b)
            try fm.copyItem(at: data.appendingPathComponent(rel), to: b)
        }
        for p in todo {
            ui.progress("寫入 \((p.rel as NSString).lastPathComponent)")
            let target = data.appendingPathComponent(p.rel)
            let tmp = target.appendingPathExtension("zhtw_tmp")
            let pf = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try b64(p.patch).write(to: pf)
            defer { try? fm.removeItem(at: pf) }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/bspatch")
            let source = upgrade.contains(p.rel) ? backup.appendingPathComponent(p.rel) : target
            proc.arguments = [source.path, tmp.path, pf.path]
            try proc.run(); proc.waitUntilExit()
            guard proc.terminationStatus == 0, sha256(tmp) == p.new else {
                try? fm.removeItem(at: tmp)
                throw PatchError(message: "\(p.rel) 寫入後驗證失敗，已中止。")
            }
            try atomicReplace(target, with: tmp)
        }
        if resTodo {
            ui.progress("重建 resources.assets（換成 \(fontNames.joined(separator: "／"))）…")
            let tmp = resURL.appendingPathExtension("zhtw_tmp")
            try? fm.removeItem(at: tmp)
            try rewriteResources(src: resURL, dst: tmp, replace: replace)
            guard verifyResources(tmp, orig: resURL, replace: replace) else {
                try? fm.removeItem(at: tmp)
                throw PatchError(message: "resources.assets 驗證失敗，已中止。")
            }
            let newSHA = sha256(tmp)!
            try atomicReplace(resURL, with: tmp)
            let m: [String: Any] = ["resources": newSHA, "fonts": fontNames, "version": 1]
            try JSONSerialization.data(withJSONObject: m, options: .prettyPrinted).write(to: marker)
        }
    } catch let e as PatchError {
        ui.fail(e.message)
    } catch {
        ui.fail(isAppManagementDenied(error) ? appManagementHelp : "安裝失敗：\(error.localizedDescription)")
    }
    ui.info("安裝完成！\n\n進遊戲後在「選項 → 語言」選「繁體中文」。\n原始檔案已備份在：\n\(backup.path)")
}

func restore(game: URL, ui: UI) {
    let fm = FileManager.default
    let data = game.appendingPathComponent("Dressmaker.app/Contents/Resources/Data")
    let backup = game.appendingPathComponent(backupDirName)
    if gameRunning() { ui.fail("請先關閉遊戲再還原。") }
    let all = smallPatches.map { ($0.rel, $0.orig) } + [(resRel, resourcesOrigSHA)]
    var restored = 0
    do {
        for (rel, orig) in all {
            if sha256(data.appendingPathComponent(rel)) == orig { continue }
            let b = backup.appendingPathComponent(rel)
            guard sha256(b) == orig else {
                throw PatchError(message: "找不到 \(rel) 的有效備份。\n請改用 Steam「驗證遊戲檔案完整性」還原。")
            }
            ui.progress("還原 \((rel as NSString).lastPathComponent)")
            let tmp = data.appendingPathComponent(rel).appendingPathExtension("zhtw_tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: b, to: tmp)
            try atomicReplace(data.appendingPathComponent(rel), with: tmp)
            restored += 1
        }
        try? fm.removeItem(at: backup.appendingPathComponent(markerName))
    } catch let e as PatchError {
        ui.fail(e.message)
    } catch {
        ui.fail(isAppManagementDenied(error) ? appManagementHelp : "還原失敗：\(error.localizedDescription)")
    }
    ui.info(restored == 0 ? "目前已經是原版檔案。" : "已還原為原版。")
}

// MARK: - 進入點

func validGame(_ u: URL) -> Bool {
    FileManager.default.fileExists(atPath: u.appendingPathComponent("Dressmaker.app/Contents/Resources/Data").path)
}

let args = Array(CommandLine.arguments.dropFirst())
if let cmd = args.first, ["install", "restore"].contains(cmd) {
    setvbuf(stdout, nil, _IONBF, 0)
    let ui = CLI()
    var game: URL?
    if let i = args.firstIndex(of: "--game"), i + 1 < args.count { game = URL(fileURLWithPath: args[i + 1]) }
    guard let g = game ?? findGame() else { ui.fail("找不到遊戲，請用 --game 指定含有 Dressmaker.app 的資料夾。") }
    guard validGame(g) else { ui.fail("這個資料夾裡沒有 Dressmaker.app：\(g.path)") }
    ui.info("遊戲位置：\(g.path)")
    cmd == "install" ? install(game: g, ui: ui) : restore(game: g, ui: ui)
} else if let cmd = args.first, !cmd.hasPrefix("-psn") {
    print("用法：zhtw-patcher install|restore [--game <含有 Dressmaker.app 的資料夾>]")
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
