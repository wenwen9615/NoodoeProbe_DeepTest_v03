# NoodoeProbe DeepTest v03 — iOS diagnostic companion

**目標**：在原廠 Noodoe 或 NewDoe 儀表上，釐清 iPhone 能否真正開啟 `EASession` 資料通道，區分 EA/Classic 與 BLE/GATT。

## 實作來源與界線

- **原廠 IPA 2.2.1 靜態分析**：`SunrayDashboard.framework` 可辨識出 `SunrayControlSession`, `SunrayDataSession`, `SunrayStream` (NSStreamDelegate), `SunrayCommandParserV1_5`, `EASession`, `EAAccessoryManager`；主程式 Info.plist 宣告 `sunray.control` 和 `sunray.data`。**沒有在本專案加入原廠任何可執行碼或資源。**
- **參考 NoodoeProbe 公開 README、project.yml**：<https://github.com/wenwen9615/NoodoeProbe>。本包是一個**獨立、可建置的實驗版本**，不是 GitHub repo 的原始完整 clone 或已合併提交。
- 使用 **公開** Apple `ExternalAccessory` + `CoreBluetooth` API。沒有越獄、沒有 private iOS API。

## 專案功能

1. `EAAccessoryManager.shared().connectedAccessories`：掃描已配對、iOS 對 APP 可用的 EA 配件。**不使用** `EABluetoothAccessoryPicker`。
2. 逐一開啟 `sunray.control` / `sunray.data` 的 `EASession` + `InputStream` / `OutputStream`；記錄 `openCompleted`, `hasSpaceAvailable`, `hasBytesAvailable`, `errorOccurred`, `endEncountered`, RX/TX Hex、累計 bytes、串流狀態。
3. BLE：掃描附近廣播、列 GATT 服務/Characteristic；手動讀取所有具 `.read` 權限的特徵值。不自動寫入、訂閱或搶占 ANCS。
4. 全程寫 Documents 目錄的 `noodoe-deep-probe-*.log`；App 內可分享。
5. 主動 TX 功能**預設關閉**，使用者須自行提供封包並兩次確認；沒有自動握手，不含任何刷寫指令。

## 操作（原廠韌體對照組）

1. 原廠官方 Noodoe APP 完全結束，iPhone 設定 → 藍牙連接 `KYMCO Noodoe`。
2. DeepProbe → `iAP 深度測試` → `重新查詢 connectedAccessories`；記錄 `Bluetooth Display Board` 的名稱及宣告協定。
3. **只開** `sunray.control` 20 秒，記錄 session 與 openCompleted；關閉。
4. **只開** `sunray.data` 20 秒，記錄相同資訊；關閉。
5. 可嘗試兩條都開，觀察是否互相干擾。
6. 在 `原始日誌` 分享 Log；不要先傳送 SPP 的五位元組握手或任何未知指令，兩種 transport 並不等價。

## 操作（NewDoe CFW 實驗組）

重複以上步驟。若 `connectedAccessories=0` 而 NewDoe 僅廣播 Classic SPP，則 iOS 的 CoreBluetooth 無法直接取得 SPP 資料流；BLE 服務清單只反映 **目前正在廣播的 BLE**，完全掃不到不能證明硬體不支援 BLE。必須進一步驗證 CFW 是否能啟用可用的 BLE GATT 通道，或請作者新增。

## 解讀結果

| 日誌 | 結論 |
| --- | --- |
| `EA connectedAccessories count=1` | iOS ExternalAccessory 可列出配件；**不代表會收發資料** |
| `EASession creation FAILED` | 此協定的 session 建立失敗 |
| `IN openCompleted` / `OUT openCompleted` | 至少對應方向的 stream 已開啟 |
| `hasSpaceAvailable` | 本地輸出緩衝可寫；**不代表儀表懂得命令** |
| `RX ... bytes` | 收到真實串流資料，後續才研究 framing / payload |
| `RX=0` | 不能直接說失敗：可能需要原廠握手 |
| `BLE Service` | 有可存取 GATT 服務；不代表可以傳 NDCP |

## 編譯 / 安裝

此環境沒有 iOS SDK/Xcode，程式僅做 Swift 語法解析驗證；**需要在 macOS GitHub Actions 編譯才可以得到 IPA**。

1. 在 GitHub 新建 repo，直接上傳本 ZIP **解壓後的內容**（含 `.github` 隱藏資料夾），推至 main。也可放在原 repo 的新 branch，但避免覆蓋原有 Claude 版本。
2. Actions → `Build unsigned DeepProbe IPA` → `Run workflow`。
3. 在該執行頁下載 artifact `NoodoeProbe-DeepTest-v03-unsigned`。
4. 透過自行持有的簽署方式安裝到 iPhone，必須保留 `UISupportedExternalAccessoryProtocols`。
5. 若 Actions 編譯失敗，將**第一個 Swift error**、或 `xcodebuild` 失敗訊息提供回來。

**隱私**：Log 可能含 MAC 對應的裝置 UUID、配件序號、通知或私人資料；公開分享前請檢查並遮蔽。
