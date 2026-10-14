# Dressmaker 繁體中文化補丁（macOS 版）

把 Steam 遊戲 **Dressmaker** 的官方簡體中文換成**繁體中文（台灣用語）**，字型使用你 Mac 內建的**蘋方-繁**（黑體）與**宋體-繁**（明體），語言選單會顯示「繁體中文」。

這是 Windows 版繁中補丁的 macOS 移植版，譯文完全相同，由同一位作者製作。

---

## 系統需求

| 項目 | 需求 |
|---|---|
| 電腦 | Apple Silicon（M1／M2／M3／M4… 系列晶片）的 Mac |
| 系統 | macOS 12 Monterey 以上 |
| 遊戲 | Steam 版 Dressmaker（Mac），遊戲版本 0.7.0（Steam build 25508059） |

> 遊戲更新後，補丁會偵測到檔案版本不同並**拒絕安裝**，不會弄壞遊戲。到時請等補丁更新。

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

**Q：顯示「檔案版本不符」？**
遊戲可能已經更新，或之前裝過其他補丁。請先在 Steam「驗證遊戲檔案完整性」再試。如果是遊戲更新了，就要等補丁更新版。

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
| `StreamingAssets/aa/StandaloneOSX/localization-string-tables-chinese(simplified)(zh-hans)_assets_all.bundle` | 4815 條簡中字串換成繁中 |
| `StreamingAssets/aa/StandaloneOSX/localization-locales_assets_all.bundle` | 語言名稱改成「繁體中文」「日本語」「English」 |
| `StreamingAssets/aa/StandaloneOSX/localization-assets-chinese(simplified)(zh-hans)_assets_all.bundle` | 傳單、報紙標題換成繁中，標題 Logo 換成英文版 |
| `StreamingAssets/aa/catalog.bin` | 上面三個 bundle 的 CRC 檢查設為 0 |
| `Managed/Assembly-CSharp.dll` | 語言選單改用自訂名稱顯示（2 bytes） |
| `resources.assets` | 中文字型換成蘋方-繁／宋體-繁，並更新對應的 TextMeshPro 字型設定；修正原版衣服標籤條在中文下不顯示標籤文字的問題 |

每個檔案在寫入前都會比對 SHA-256，寫入後會再驗證一次，任何一步失敗都會中止，不會留下改到一半的檔案。

---

## 給維護者：遊戲更新後重新製作

需要：Xcode（swiftc）、Homebrew 的 `bsdiff`，以及一個裝了 `UnityPy`、`TypeTreeGeneratorAPI`、`fonttools` 的 Python 3.12 venv。

```bash
# 1. 用 tools/port_zhTW.py 從新版原檔產生補丁後的檔案（需要 Windows 版補丁的 payload）
python tools/port_zhTW.py <原版 Data 資料夾> <payload 資料夾> <輸出資料夾>

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

## 授權與致謝

- 繁體中文翻譯：本補丁作者（Windows 版、macOS 版同一人）。
- Dressmaker 版權屬於原開發商，本補丁僅供已購買遊戲的玩家使用，不包含任何遊戲原始檔案。
- 補丁不包含任何字型檔，蘋方-繁與宋體-繁由使用者 Mac 上的系統提供。
