# 自由軟體應用 W12｜GitHub Actions 自動化測試（學生版）

## 學習目標
1. 能用 Python 執行庫存判斷程式。
2. 能使用 pytest 執行單元測試，解釋 `passed` 與 `failed`。
3. 能將程式上傳至 GitHub，並在 Actions 頁面確認自動測試結果。
4. 能保留失敗與修正成功的證據，說明持續整合（CI）的價值。

## 這個 ZIP 內有什麼？
- `inventory.py`：庫存補貨邏輯，低於門檻才補貨。
- `products.json`：範例商品資料。
- `test_inventory.py`：六個 pytest 測試案例。
- `requirements.txt`：測試所需套件。
- `.github/workflows/python-tests.yml`：GitHub Actions 工作流程（**隱藏資料夾，請保留完整路徑**）。
- `README.md`：本操作說明。

## A. 建立個人儲存庫
1. 先下載 ZIP 並解壓縮；**不要只上傳 ZIP 檔**。
2. 登入 GitHub → 右上角 `+` → `New repository`。
3. 儲存庫命名建議 `W12-GitHub-Actions-學號`（依教師規定），建議設為 Private；若 Private，請授予教師檢視權限。請勿把帳密或個資寫入檔案。
4. 建立後選 `uploading an existing file`，將解壓後的檔案與 `.github/workflows/python-tests.yml` 一起上傳；如果網頁上傳漏掉隱藏的 `.github`，請使用 Codespaces 建立該路徑，或在 GitHub `Add file` → `Create new file`，輸入完整檔名 `.github/workflows/python-tests.yml` 並貼入內容。
5. 點 `Commit changes`，確認 Code 頁面能看見 `.github/workflows/python-tests.yml`。

## B. Codespaces 執行
在自己的儲存庫按 `Code` → `Codespaces` → `Create codespace on main`。等終端機出現後，依序輸入：

```bash
python --version
python -m pip install -r requirements.txt
python inventory.py
python -m pytest -v
```

預期看到「需要補貨的商品： 筆記本」及 `6 passed`（實際版本、時間可能不同）。若 `python` 指令不可用，試用 `python3`。

## C. GitHub Actions 自動測試
1. 回到 GitHub 儲存庫，點 `Actions`。
2. 找到 `Python tests`，進入最近一次執行，點 `test` 工作。
3. 綠色勾代表測試通過；紅色叉代表失敗。若沒有執行，確認 workflow 檔案已提交至 `.github/workflows/`，並檢查儲存庫 Actions 設定是否允許執行。
4. 截圖保留成功執行紀錄。

## D. 故意製造失敗，再修復
1. 在 `inventory.py` 中，把 `return quantity < threshold` **暫時**改成 `return quantity > threshold`。
2. 存檔並提交：

```bash
git add inventory.py
git commit -m "W12 demonstrate failing test"
git push
```

3. 到 GitHub `Actions` 等候結果，開啟失敗工作，截圖紅色叉及 `FAILED` 的測試資訊。
4. 把程式改回 `return quantity < threshold`，再次提交：

```bash
git add inventory.py
git commit -m "W12 fix inventory logic"
git push
```

5. 確認 Actions 再次變綠色，截圖成功紀錄。**務必修復後再繳交**。

> 注意：如果 `git commit` 顯示 `nothing to commit`，代表尚未儲存或沒有實際變更；如果 `git push` 失敗，先檢查是否在自己的儲存庫、是否已登入以及網路狀態。不要使用 `git push --force`。

## E. 自主練習
1. 在 `test_inventory.py` 新增 `test_zero_quantity`，驗證庫存 0 時需要補貨。
2. 新增 `test_threshold_zero`，驗證庫存 0、門檻 0 時不補貨。
3. 將新增的兩個測試提交並推送，Actions 應顯示 `8 passed`。
4. 用自己的話說明：為什麼每次 push 都自動執行測試，有助於團隊開發？

## F. ee-class 繳交
依教師提供的 Word 練習單填寫，並繳交：
- 個人 GitHub 儲存庫連結（Private 請先授權教師）。
- 終端機測試通過截圖。
- Actions **失敗**截圖與修復後**成功**截圖。
- 新增兩項測試的程式截圖，以及簡短心得。

**提醒：** Actions 執行會使用 GitHub 提供的運算資源，請避免無意義的反覆提交；如果學校網路或帳號政策限制 Actions，請向教師回報並保留終端機測試結果。
