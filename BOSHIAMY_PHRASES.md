# 嘸蝦米：候選列的常用詞與聯想

iOS 版（本 repo，`voice-key-m0` 分支）與 Android 版（Trime `boshiamy` 分支）都已實作。

> **2026-11-07 改版**（使用者在小米 15 Ultra 實機確認後要求，Android 1.1.0-5 與 iOS 同步）：
> 沒在打字時候選列中間保持空白，**不再主動顯示常用詞**；只在剛上屏後顯示使用者自己的接續，**不再用詞庫補詞**。
> 下面「常用詞」排序規則（`commonPhrases`）目前沒有地方用到，先保留。

## 功能

| 狀態 | 候選列中間顯示 | 點一下 |
|---|---|---|
| 沒在打字、也沒剛上屏 | **空白**（只有左邊的按鈕和右邊的繁／中） | — |
| 剛上屏 | 以剛上屏的字詞開頭、或常接在它後面的**使用者常用詞**，顯示整個詞（上屏「永」→「永盈」） | 只送出還沒上屏的部分（「盈」），再以整個詞「永盈」當開頭接著聯想 |
| 正在打嘸蝦米碼 | RIME 候選（**順序固定**，方案 `enable_user_dict: false`，不自動調頻） | 照舊 |

- 「繁」「中」兩個切換按鈕**固定在候選列最右邊**（打字時也在），左側和中間給候選字與常用詞。
- 聯想出現後，按鍵盤上的**任何鍵**（包括開始打新字根）就消失，候選列中間回到空白。

## 隱私

- 記錄只存在手機本機：App Group 容器 `BoshiamyPhrases/phrases.json`。程式裡沒有任何網路呼叫。
  鍵盤沒開「允許完整取用」時寫不進 App Group，改存鍵盤自己的沙箱（主 App 的「清除記錄」清不到那份，但它只在鍵盤裡）。
- `isSecureTextEntry`、`textContentType` 為 password／newPassword／oneTimeCode 的欄位：不記錄、也不顯示。
- 設定頁「鍵盤設定 → 中文鍵盤」最上面：「常用詞與聯想」開關（`keyboard.enableBoshiamyPhraseSuggestion`，預設開）、「清除記錄」按鈕。
- 清除：主 App 刪檔，並在 App Group 的 UserDefaults 寫 `boshiamy.phrase.clearedAt`；鍵盤載入／存檔前比對這個時間，丟掉記憶體裡的舊資料，避免寫回。

## 記錄方式（`BoshiamyPhraseStore`）

嘸蝦米一次上屏一個字，所以「詞」要從連續上屏的字裡統計出來：

1. **連續段**：連續上屏的漢字算同一段；遇到標點、空白、英文、刪除鍵、Enter、符號鍵、換欄位就切斷。
   正在組字時按的鍵（包括選字的空白、數字）和中文模式的字母鍵不切斷。
2. **words**：每多一個字，把以它結尾的 1–4 字片段各記一次（次數 `c`、最後使用時間 `t`），
   並記錄片段出現在連續段**開頭**的次數 `s`（在開頭出現的比較像一個詞）。
3. **follows**：「前 1 字」和「前 2 字」→ 接在後面的 1–3 字片段，各記一次。
4. 上限：words 4000 筆、follows 1500 個上文 × 每個 20 筆，超過就把分數低的刪掉。存檔延遲 3 秒、鍵盤消失時立即存。

### 排序

- 分數 = 次數 × 0.5^(天數/30) ＋ 3 × e^(−天數)（最近用過加分）。
- **常用詞**
  - 多字片段至少出現 2 次。分數 × 1.5 × (1 + 開頭比例)。
  - 次數相近（≥ 80%）又互相包含或頭尾重疊的片段（「我們今天」／「們今天去」）只留分數最高的。
  - 單字的次數要扣掉它在已選常用詞裡出現的次數，只算單獨使用的部分。
  - 前 10 名不到 2 個單字時，用單字換掉排最後的詞。
- **聯想**
  - 前 2 字上文的接續 × 2，加上前 1 字上文的接續。2 字以上 × 1.3。
  - 跨詞的接續不要：接續的第一個字跟上文黏得比跟下一個字更緊（「我」→「們今」：「我們」遠比「們今」常見）。
  - 次數相近的同一串（「今」「今天」「今天去」）留最短的多字版本。
  - ~~不足 10 個時用 `boshiamy_assoc.txt` 補~~（2026-11-07 起不補；Android 仍用詞庫判斷接續有沒有跨詞）。

### 詞庫（`boshiamy_assoc.txt`，2026-11-07 起 iOS 不再使用，資料檔先保留）

- 由 `BoshiamyAssocBuild.py` 從 rime-essay 的 `essay.txt`（`.tmp/SharedSupport/essay.txt`，InputSchemaBuild.sh 產生）產生，
  用 `.deps/bin/opencc` 的 t2tw 轉成台灣用字（為、啟）。
- 格式：`首字<TAB>接續1<TAB>接續2…`，每個首字取權重最高的 12 個 2–4 字詞（去掉首字）。約 6000 行、250 KB。
- 重新產生：`DYLD_LIBRARY_PATH=.deps/lib python3 BoshiamyAssocBuild.py`。

### 打繁出簡

使用者記錄存的是實際上屏的字。打繁出簡模式下，顯示的詞用 OpenCC `t2s` 轉成簡體。

## 程式位置（iOS）

| 檔案 | 內容 |
|---|---|
| `Packages/HamsterKeyboardKit/Sources/Boshiamy/BoshiamyPhraseStore.swift` | 記錄、排序、存檔、清除 |
| `Packages/HamsterKeyboardKit/Sources/Boshiamy/BoshiamyPhraseSuggestion.swift` | 上屏後顯示「開頭＋接續」、點選只送接續、OpenCC |
| `Packages/HamsterKeyboardKit/Sources/View/BoshiamyPhraseBarView.swift` | 候選列中間的橫向捲動列 |
| `Packages/HamsterKeyboardKit/Sources/View/KeyboardToolbarView.swift` | 版面：繁／中固定在最右邊 |
| `Packages/HamsterKeyboardKit/Sources/Controller/KeyboardInputViewController.swift` | 上屏後 `didCommit`、密碼欄位判斷、鍵盤出現／消失 |
| `Packages/HamsterKeyboardKit/Sources/KeyboardKit/Actions/StandardKeyboardActionHandler.swift` | 任何按鍵 → `boshiamyKeyPressed`（聯想消失） |
| `Packages/HamsteriOS/Sources/ViewModel/Keyboard/KeyboardSettingsViewModel.swift` | 設定開關與清除按鈕 |
| `Packages/HamsterKeyboardKit/Sources/Resources/boshiamy_assoc.txt` | 詞庫資料（目前 iOS 沒用到） |

## Android 版（Trime）做法（已完成；這節是當初的移植筆記）

演算法、檔案格式、排序規則都照上面，直接把 Swift 移植成 Kotlin。差別只在掛載點：

1. **儲存**：`context.filesDir/boshiamy_phrases.json`（App 私有目錄，本來就只有本機），格式同 iOS 的 `phrases.json`。
   清除直接刪檔並清空記憶體（同一個程序，不需要 clearedAt）。
2. **上屏 hook**：`TrimeInputMethodService.commitText(text)`（`ime/core/TrimeInputMethodService.kt`）
   成功送出後呼叫 `PhraseSuggestion.didCommit(text)`。
3. **切斷連續段**：`onStartInput`（換欄位）、`onUpdateSelection` 遊標不是剛好在上屏位置之後、
   刪除鍵／Enter／空白（組字中除外）／符號鍵（`CommonKeyboardActionListener` 的按鍵處理入口）。
4. **密碼欄位**：`EditorInfo.inputType` 的 variation 是 `TYPE_TEXT_VARIATION_PASSWORD`、`VISIBLE_PASSWORD`、
   `WEB_PASSWORD`、`TYPE_NUMBER_VARIATION_PASSWORD`，或 `imeOptions` 有 `IME_FLAG_NO_PERSONALIZED_LEARNING`（無痕模式）時，不記錄也不顯示。
5. **候選列版面**：Trime 沒在打字時顯示 `ime/bar/ui/AlwaysUi.kt`（QuickBar 的常駐列），
   在這裡加一個橫向 RecyclerView（常用詞／聯想），右邊放「繁」「中」兩個按鈕。
   打字時的 `CandidateUi.kt` 右邊也保留這兩個按鈕。狀態切換看 `QuickBarStateMachine.kt`。
   目前「繁」「中」是鍵盤上的 `Boshiamy_simp`／`Boshiamy_ascii` 鍵，移到候選列後可以保留或拿掉，由使用者決定。
6. **聯想消失**：任何按鍵（`CommonKeyboardActionListener` 的 onPress 類事件）都回到常用詞。
7. **詞庫補詞**：把同一份 `boshiamy_assoc.txt` 放進 `app/src/main/assets/`，第一次需要時讀進 `HashMap<Char, List<String>>`。
8. **打繁出簡**：Trime 的 librime 已經帶 OpenCC。可以用 RIME 的 simplifier 結果，或在 Kotlin 端 JNI 呼叫 OpenCC `t2s`／`s2t`
   （Trime 已編進 `librime_jni`，看能不能直接用 `opencc` 的 C API）。
9. **設定**：`AppPrefs.kt` 加 `boshiamy_phrase_suggestion`（預設 true）與「清除記錄」，放在「鍵盤」設定頁。
10. **不自動調頻**：Android 的 `boshiamy.schema.yaml` 已經是 `enable_user_dict: false`，維持不動。
