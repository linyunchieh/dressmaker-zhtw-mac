# Dressmaker 繁體中文化補丁（macOS 版）

把 Steam 遊戲 **Dressmaker** 的官方簡體中文換成**繁體中文（台灣用語）**，字型使用你 Mac 內建的**蘋方-繁**（黑體）與**宋體-繁**（明體），語言選單會顯示「繁體中文」。

這是 Windows 版繁中補丁的 macOS 移植版，由同一位作者製作；遊戲更新新增的字串也已補上繁中。

---

## 系統需求

| 項目 | 需求 |
|---|---|
| 電腦 | Apple Silicon（M1／M2／M3／M4… 系列晶片）的 Mac |
| 系統 | macOS 12 Monterey 以上 |
| 遊戲 | Steam 版 Dressmaker（Mac），遊戲版本 0.7.0（製作時為 Steam build 25936486，2026-10-14 更新） |

> **遊戲更新後**：Steam 會把補丁改過的檔案蓋回原版，畫面會變回簡體中文，**再執行一次安裝就好**。
> 從 2.2 起，補丁不再比對整個檔案，而是直接找出要修改的那幾處，只要遊戲的小更新（hotfix）沒有動到翻譯和字型，舊版補丁也能直接安裝。
> 如果更新剛好動到補丁要改的地方，安裝程式會列出是哪一項不符並**拒絕安裝**，不會弄壞遊戲；遇到這種情況，請等補丁更新。

---

## 安裝方式（擇一）

安裝前請先**關閉遊戲**。

### 方式一：終端機一行指令（推薦，最省事）

1. 打開「終端機」（在 Launchpad 或「應用程式 → 工具程式」裡）。
2. 貼上下面這行，按 Enter：

```bash
curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash
```

看到「安裝完成！」就好了。這個方式不會跳出「無法驗證開發者」的警告。

### 方式二：下載 app 雙擊安裝

1. 到 [Releases](https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest) 下載 `Dressmaker-zhTW-mac-app.zip`，解壓縮後會得到 `Dressmaker繁中補丁.app`。
2. 雙擊打開。因為這個 app 沒有經過 Apple 公證，第一次打開時 macOS 會擋下來，請依照你的系統版本操作：
   - **macOS 15 Sequoia 以上**：看到警告後按「完成」→ 打開「系統設定 → 隱私權與安全性」→ 捲到最下面，在「已阻擋 Dressmaker繁中補丁」旁按「**仍要打開**」→ 輸入登入密碼。
   - **macOS 14 以前**：在 app 上按右鍵（或 Control＋點按）→「打開」→ 再按一次「打開」。
3. 在對話框按「安裝繁體中文」。

只有第一次需要這樣做，之後都可以直接雙擊。

---

## 進遊戲設定

打開遊戲 →「選項 → 語言」→ 選「**繁體中文**」。

（補丁是把「簡體中文」那一格換成繁中，所以原本的簡體中文會被取代。）

---

## 還原成原版

- **終端機**：

  ```bash
  curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash -s restore
  ```

- **app**：雙擊 → 按「還原原版」。
- **都不行的話**：在 Steam 的遊戲上按右鍵 →「內容 → 已安裝檔案 → 驗證遊戲檔案完整性」，也能完全還原。

安裝時，原始檔案會備份在遊戲資料夾裡的 `_zhTW_backup`。

---

## 常見問題

**Q：遊戲更新後又變回簡體中文？**
Steam 更新會把檔案蓋回原版，再執行一次安裝即可（不用重新下載補丁）。

**Q：顯示「以下檔案無法套用」？**
遊戲的更新動到了補丁要改的地方（例如新增了字串），或之前裝過其他補丁。請先在 Steam「驗證遊戲檔案完整性」再試；如果還是一樣，就要等補丁更新版。
想先確認能不能安裝（不會改動任何檔案）：

```bash
curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash -s check
```

**Q：顯示「macOS 拒絕修改遊戲檔案（App 管理）」？**
到「系統設定 → 隱私權與安全性 → App 管理」，打開「終端機」（方式一）或「Dressmaker繁中補丁」（方式二）的開關，再執行一次。

**Q：顯示「找不到遊戲」？**
補丁會自動搜尋所有 Steam 遊戲庫。如果還是找不到：
- app 版：會跳出視窗讓你選擇遊戲資料夾（裡面有 `Dressmaker.app` 的那一層）。
- 終端機版：在指令後面加上資料夾位置：

  ```bash
  curl -fsSL https://github.com/linyunchieh/dressmaker-zhtw-mac/releases/latest/download/install.sh | bash -s install --game "/你的/SteamLibrary/steamapps/common/Dressmaker"
  ```

**Q：顯示「找不到系統字型」？**
打開「字體簿」，搜尋「蘋方-繁」與「宋體-繁」，如果出現下載按鈕就按下載，完成後再安裝一次。

**Q：Intel Mac 可以用嗎？**
這個版本只支援 Apple Silicon。

**Q：為什麼字型不直接包在補丁裡？**
蘋方與宋體是 Apple 的系統字型，授權只允許在 Mac 上使用，不允許另外散布。所以補丁本身不含任何字型檔，而是在安裝時從**你自己的 Mac** 讀取內建字型寫進遊戲，每台 Mac 都內建這兩套字型。

---

## 補丁改了哪些東西

全部在 `Dressmaker.app/Contents/Resources/Data/` 底下：

| 檔案 | 內容 |
|---|---|
| `StreamingAssets/aa/StandaloneOSX/localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle` | 4841 條簡中字串換成繁中 |
| `StreamingAssets/aa/StandaloneOSX/localization-locales_assets_all.bundle` | 語言名稱改成「繁體中文」「日本語」「English」 |
| `StreamingAssets/aa/StandaloneOSX/localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle` | 傳單、報紙標題換成繁中，標題 Logo 換成英文版 |
| `StreamingAssets/aa/catalog.bin` | 上面三個 bundle 的 CRC 檢查設為 0 |
| `Managed/Assembly-CSharp.dll` | 語言選單改用自訂名稱顯示（2 bytes） |
| `resources.assets` | 中文字型換成蘋方-繁／宋體-繁，並更新對應的 TextMeshPro 字型設定；修正原版衣服標籤條在中文下不顯示標籤文字的問題 |

寫入前的檢查方式：三個 bundle 比對整個檔案的 SHA-256（內容有變就代表譯文需要更新）；DLL 搜尋那段程式碼、catalog.bin 搜尋那三筆記錄，都必須剛好找到一處；resources.assets 解析物件表、依名稱找出字型與 LocaleFontFallbacks，再比對這幾個物件本身的 SHA-256。所以遊戲 hotfix 只改了別的地方時，照樣可以安裝。寫入後每個檔案都會再驗證一次，任何一步失敗都會中止，不會留下改到一半的檔案。

---

## 給維護者：遊戲更新後重新製作

需要：Xcode（swiftc）、Homebrew 的 `bsdiff`，以及一個裝了 `UnityPy`、`TypeTreeGeneratorAPI`、`fonttools` 的 Python 3.12 venv。

```bash
# 1. 用 tools/port_zhTW.py 從新版原檔產生補丁後的檔案（需要 Windows 版補丁的 payload）
#    先把 MAC_ORIG 換成新版原檔的 SHA-256；遊戲新增或改過的字串補進 TC_OVERRIDES（缺譯文時會列出來並停止）
python tools/port_zhTW.py <原版 Data 資料夾> <payload 資料夾> <輸出資料夾>

# 0. 遊戲更新後先檢查：全部 ✓ 就不用出新版
build/zhtw-patcher check

# 2. 重新產生內嵌資料並編譯、打包
ORIG=<原版 Data> NEW=<輸出資料夾> VENV=<venv> REPO=<帳號>/dressmaker-zhtw-mac ./build.sh regen
```

產出在 `dist/`：

| 檔案 | 用途 |
|---|---|
| `install.sh` | 終端機安裝腳本 |
| `zhtw-patcher-arm64` | 命令列工具（install.sh 會下載它） |
| `Dressmaker-zhTW-mac-app.zip` | 雙擊用的 app |
| `SHA256SUMS.txt` | 校驗碼 |

四個檔案全部上傳到同一個 GitHub Release。

如果之後有 Apple Developer Program（付費）帳號，可以用 Developer ID 簽章並公證，這樣 app 就不會被 Gatekeeper 擋：

```bash
SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)" ./build.sh
xcrun notarytool submit dist/Dressmaker-zhTW-mac-app.zip --keychain-profile <設定檔> --wait
```

（公證通過後，再對解壓出來的 app 執行 `xcrun stapler staple`，然後重新壓縮。）

---

## 更新紀錄

- **2.3.0**（2026-10-15）：服裝術語改用台灣服裝業的說法，約 740 條：連衣裙／裙裝→洋裝、鉛筆裙襬等款式→鉛筆裙（部件→裙片）、衣身→上身、嵌線→出芽、育克→剪接、紙樣→版型（繪製紙樣→打版）、漸變→漸層、紐扣→鈕釦、羊毛呢→毛呢、棋盤格→格子、海軍領→水手領、氣眼→雞眼、燈芯絨→燈心絨、晚裝→晚禮服等。修正 Black Gingham Trim 誤譯為「藍色」，Cap Sleeve 改譯「蓋袖」（原本和 Short Sleeve 一樣都是「短袖」）。從 2.2.0 升級直接重新執行安裝即可。
- **2.2.0**（2026-10-15）：譯名「製衣師」改為「裁縫師」（製衣店→裁縫店等，所有「製衣」統一改為「裁縫」）。安裝程式改成直接找出要修改的地方，遊戲小更新後不必等補丁更新，重新執行安裝即可；新增 `check` 指令。從 2.1.x 升級直接重新執行安裝即可。
- **2.1.1**（2026-10-14）：支援遊戲 build 25936486（當天第二次更新，只動到程式與資源檔，譯文沒變）。從 2.1.0 升級直接重新執行安裝即可。
- **2.1.0**（2026-10-14）：支援遊戲 build 25928714。補上新版新增的 27 條字串（設定頁「遊戲玩法／畫面／音效」、減少動畫效果、光暈、鏡頭操作、設計簿翻頁等）與 4 條原文有改動的字串（「報酬」「作為成衣出售」、兩段教學）。從 2.0 升級直接重新執行安裝即可。
- **2.0.0**（2026-10-14）：「哥特」改為「哥德」、傳單／報紙標題繁中化、標題 Logo 改英文版、修正衣服標籤條中文不顯示。
- **1.0.0**（2026-10-14）：首次發布。

---

## 授權與致謝

- 繁體中文翻譯：本補丁作者（Windows 版、macOS 版同一人）。
- Dressmaker 版權屬於原開發商，本補丁僅供已購買遊戲的玩家使用，不包含任何遊戲原始檔案。
- 補丁不包含任何字型檔，蘋方-繁與宋體-繁由使用者 Mac 上的系統提供。
