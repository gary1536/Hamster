//
//  BoshiamyPhraseStore.swift
//  HamsterKeyboardKit
//
//  Gary fork：嘸蝦米「常用詞」與「聯想」的本機統計。
//
//  - 只存在手機本機：App Group 容器裡的 BoshiamyPhrases/phrases.json（沒有網路程式碼）。
//    鍵盤沒有「允許完整取用」時寫不進 App Group，改存鍵盤自己的沙箱。
//  - 記錄方式：連續上屏的漢字（中間沒有標點、空白、英文、刪除、游標移動）視為同一段，
//    每多一個字，就把以它結尾的 1–4 字片段計數一次（words），
//    並記錄「前 1 字／前 2 字 → 這個 1–3 字片段」的接續次數（follows），供聯想使用。
//  - 排序：上屏次數 × 時間衰減（半衰期 30 天）＋ 最近使用加分；2–4 字詞加權優先。
//  - 清除：主 App 呼叫 clearAll()，刪檔並在 App Group 的 UserDefaults 記下清除時間；
//    鍵盤載入或存檔前比對清除時間，丟掉記憶體裡的舊資料，避免把清掉的記錄寫回去。
//

import Foundation
import HamsterKit

public final class BoshiamyPhraseStore {
  public static let shared = BoshiamyPhraseStore()

  // MARK: - 資料結構

  struct Entry: Codable {
    /// 次數
    var c: Double
    /// 最後使用時間（epoch 秒）
    var t: Double
    /// 出現在連續段開頭的次數（比較像一個詞的開頭，用來分辨「我們今天」和跨詞的「們今天去」）
    var s: Double = 0
  }

  struct Snapshot: Codable {
    var v: Int = 1
    var words: [String: Entry] = [:]
    var follows: [String: [String: Entry]] = [:]
  }

  // MARK: - 常數

  static let clearedAtKey = "boshiamy.phrase.clearedAt"
  private static let maxWords = 4000
  private static let maxFollowKeys = 1500
  private static let maxFollowsPerKey = 20
  private static let halfLifeDays = 30.0

  // MARK: - 狀態

  private var snapshot = Snapshot()
  private var loaded = false
  private var loadedAt: Double = 0
  private var fileModifiedAt: Date?
  private var dirty = false
  private var saveWorkItem: DispatchWorkItem?
  private let ioQueue = DispatchQueue(label: "boshiamy.phrase.io")
  /// 目前這一段連續上屏的漢字（最多 6 個）
  private var recent: [Character] = []
  /// 目前這一段總共上屏了幾個漢字（不受 6 個上限影響）
  private var runLength = 0

  private init() {}

  // MARK: - 檔案位置

  private static var appGroupFileURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName)?
      .appendingPathComponent("BoshiamyPhrases", isDirectory: true)
      .appendingPathComponent("phrases.json")
  }

  private static var sandboxFileURL: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("BoshiamyPhrases", isDirectory: true)
      .appendingPathComponent("phrases.json")
  }

  /// 優先用 App Group；目錄建不起來（沒有完整取用）就用沙箱
  private lazy var fileURL: URL = {
    if let url = Self.appGroupFileURL {
      let dir = url.deletingLastPathComponent()
      do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let probe = dir.appendingPathComponent(".probe")
        try Data().write(to: probe)
        try? FileManager.default.removeItem(at: probe)
        return url
      } catch {
        FileManager.hamsterDiag("[phrase] app group not writable, use sandbox: \(error.localizedDescription)")
      }
    }
    let url = Self.sandboxFileURL
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    return url
  }()

  private static var clearedAt: Double {
    UserDefaults.hamster.double(forKey: clearedAtKey)
  }

  // MARK: - 主 App：清除

  /// 清除所有記錄（主 App 設定頁呼叫）。鍵盤下次出現時會丟掉記憶體裡的資料。
  public static func clearAll() {
    UserDefaults.hamster.set(Date().timeIntervalSince1970, forKey: clearedAtKey)
    if let url = appGroupFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    try? FileManager.default.removeItem(at: sandboxFileURL)
    shared.resetInMemory()
  }

  // MARK: - 載入／存檔

  /// 鍵盤出現時呼叫：檔案有變（例如被主 App 清除）就重新載入
  public func reloadIfNeeded() {
    if loaded, Self.clearedAt > loadedAt {
      resetInMemory()
    }
    let modified = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    if loaded, modified == fileModifiedAt { return }
    if loaded, dirty { return } // 記憶體比檔案新，保留記憶體的
    load()
  }

  private func load() {
    loaded = true
    loadedAt = Date().timeIntervalSince1970
    let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    fileModifiedAt = attrs?[.modificationDate] as? Date
    guard let data = try? Data(contentsOf: fileURL) else {
      snapshot = Snapshot()
      return
    }
    do {
      snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
    } catch {
      FileManager.hamsterDiag("[phrase] decode failed, start fresh: \(error.localizedDescription)")
      snapshot = Snapshot()
    }
  }

  private func resetInMemory() {
    snapshot = Snapshot()
    recent.removeAll()
    runLength = 0
    dirty = false
    saveWorkItem?.cancel()
    loadedAt = Date().timeIntervalSince1970
  }

  /// 延遲 3 秒存檔（連續打字時只寫一次）
  private func scheduleSave() {
    dirty = true
    saveWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.saveNow() }
    saveWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
  }

  /// 立即存檔（鍵盤消失時呼叫）
  public func saveNow() {
    saveWorkItem?.cancel()
    guard dirty else { return }
    if Self.clearedAt > loadedAt {
      // 存檔前發現主 App 已清除：丟掉舊資料，不寫回
      resetInMemory()
      return
    }
    prune()
    dirty = false
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    let url = fileURL
    ioQueue.async { [weak self] in
      do {
        try data.write(to: url, options: .atomic)
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        DispatchQueue.main.async { self?.fileModifiedAt = modified }
      } catch {
        FileManager.hamsterDiag("[phrase] save failed: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - 記錄

  /// 記錄一次上屏。非漢字（標點、空白、英文）會切斷連續段。
  public func record(_ text: String) {
    if !loaded { load() }
    let now = Date().timeIntervalSince1970
    var changed = false
    for ch in text {
      if Self.isHan(ch) {
        append(ch, now: now)
        changed = true
      } else {
        recent.removeAll()
        runLength = 0
      }
    }
    if changed { scheduleSave() }
  }

  /// 中斷連續段（刪除、空白、Enter、游標移動、切換欄位等）
  public func breakContext() {
    recent.removeAll()
    runLength = 0
  }

  /// 目前連續段最後的漢字（聯想用的上文）
  public var currentContext: String {
    String(recent.suffix(2))
  }

  private func append(_ ch: Character, now: Double) {
    recent.append(ch)
    runLength += 1
    if recent.count > 6 { recent.removeFirst(recent.count - 6) }
    let n = recent.count
    for len in 1 ... min(4, n) {
      let start = n - len
      let gram = String(recent[start ..< n])
      Self.bump(&snapshot.words, gram, now: now, isRunStart: runLength == len)
      // 聯想：前 1 字／前 2 字 → 這段（1–3 字）
      if len <= 3 {
        if start >= 1 {
          Self.bump(&snapshot.follows[String(recent[start - 1]), default: [:]], gram, now: now)
        }
        if start >= 2 {
          Self.bump(&snapshot.follows[String(recent[start - 2 ..< start]), default: [:]], gram, now: now)
        }
      }
    }
  }

  private static func bump(_ dict: inout [String: Entry], _ key: String, now: Double, isRunStart: Bool = false) {
    var entry = dict[key] ?? Entry(c: 0, t: now)
    entry.c += 1
    entry.t = now
    if isRunStart { entry.s += 1 }
    dict[key] = entry
  }

  // MARK: - 排序

  private static func score(_ entry: Entry, now: Double) -> Double {
    let ageDays = max(0, now - entry.t) / 86400
    let decayed = entry.c * pow(0.5, ageDays / halfLifeDays)
    // 最近使用加分：剛用過 +3，約 1 天後降到 1 左右
    let recency = 3 * exp(-ageDays)
    return decayed + recency
  }

  /// 聯想的接續片段都從同一個位置開始，次數相近時是同一串字的不同長度：
  /// 有 2 字以上的版本就不要單字；多字版本中留最短的。
  private static func preferShortContinuations(_ items: [(String, Entry)]) -> [(String, Entry)] {
    items.filter { word, entry in
      !items.contains { other, otherEntry in
        guard other != word, other.hasPrefix(word) || word.hasPrefix(other) else { return false }
        let ratio = min(entry.c, otherEntry.c) / max(entry.c, otherEntry.c)
        guard ratio >= 0.8 else { return false }
        if word.count == 1 { return other.count == 2 } // 單字讓給 2 字版本
        return other.count >= 2 && other.count < word.count // 多字留最短的
      }
    }
  }

  /// 去掉「幾乎總是跟著更長片段一起出現」的片段（例如只打過「我們今天」時，不列出「們今」）
  private static func removeFragments(_ items: [(String, Entry)]) -> [(String, Entry)] {
    let multi = items.filter { $0.0.count >= 2 }
    return items.filter { word, entry in
      guard word.count >= 2 else { return true }
      return !multi.contains { other, otherEntry in
        other.count > word.count && other.contains(word) && otherEntry.c >= entry.c * 0.8
      }
    }
  }

  /// 兩個片段是否互相包含或頭尾重疊（例如「我們今天」與「們今天去」、「今天」與「天去」）
  private static func overlaps(_ a: String, _ b: String) -> Bool {
    if a.contains(b) || b.contains(a) { return true }
    let x = Array(a), y = Array(b)
    for k in 1 ..< min(x.count, y.count) {
      if Array(x.suffix(k)) == Array(y.prefix(k)) || Array(y.suffix(k)) == Array(x.prefix(k)) { return true }
    }
    return false
  }

  /// 常用詞：2–4 字詞優先，也保留單字（至少 2 個，若有的話）
  public func commonPhrases(limit: Int = 10) -> [String] {
    if !loaded { load() }
    let now = Date().timeIntervalSince1970

    // 多字片段：出現 2 次以上才算；在連續段開頭出現得越多越像詞
    let multiCandidates = snapshot.words
      .filter { $0.key.count >= 2 && $0.value.c >= 2 }
      .map { word, entry -> (String, Entry, Double) in
        let startRatio = min(1, entry.s / max(entry.c, 1))
        return (word, entry, Self.score(entry, now: now) * 1.5 * (1 + startRatio))
      }
      .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0.count > $1.0.count }
      .prefix(300)

    // 次數相近又重疊的片段，視為同一段話的不同切法，只留分數最高的
    var acceptedMulti: [(String, Entry, Double)] = []
    for candidate in multiCandidates {
      let conflict = acceptedMulti.contains { other in
        let ratio = min(candidate.1.c, other.1.c) / max(candidate.1.c, other.1.c)
        return ratio >= 0.8 && Self.overlaps(candidate.0, other.0)
      }
      if !conflict { acceptedMulti.append(candidate) }
      if acceptedMulti.count >= limit * 2 { break }
    }

    // 單字：扣掉它在常用詞裡出現的次數，只算單獨使用的部分
    var singles: [(String, Double)] = []
    for (word, entry) in snapshot.words where word.count == 1 {
      let ch = word.first!
      let inside = acceptedMulti.reduce(0.0) { sum, item in
        sum + item.1.c * Double(item.0.filter { $0 == ch }.count)
      }
      var standalone = entry
      standalone.c = entry.c - inside
      guard standalone.c >= 1 else { continue }
      singles.append((word, Self.score(standalone, now: now)))
    }
    singles.sort { $0.1 > $1.1 }

    var ranked = acceptedMulti.map { ($0.0, $0.2, false) } + singles.map { ($0.0, $0.1, true) }
    ranked.sort { $0.1 > $1.1 }

    var result = Array(ranked.prefix(limit))
    // 單字也要：前 limit 名沒有 2 個單字時，用最常用的單字換掉排最後的詞
    let singlesInResult = result.filter { $0.2 }.count
    if singlesInResult < 2 {
      let extraSingles = ranked.dropFirst(limit).filter { $0.2 }.prefix(2 - singlesInResult)
      for single in extraSingles {
        if let index = result.lastIndex(where: { !$0.2 }) {
          result.remove(at: index)
        }
        result.append(single)
      }
    }
    return result.map { $0.0 }
  }

  /// 聯想：使用者最常接在 context（最後 1–2 個字）後面的片段
  public func userAssociations(after context: String, limit: Int = 10) -> [String] {
    if !loaded { load() }
    guard let last = context.last else { return [] }
    let now = Date().timeIntervalSince1970
    var scores: [String: Double] = [:]
    var entries: [String: Entry] = [:]
    // 前 2 字的接續比前 1 字可靠，加權較高
    if context.count >= 2, let map = snapshot.follows[String(context.suffix(2))] {
      for (gram, entry) in map {
        scores[gram, default: 0] += Self.score(entry, now: now) * 2
        entries[gram] = entry
      }
    }
    if let map = snapshot.follows[String(last)] {
      for (gram, entry) in map {
        scores[gram, default: 0] += Self.score(entry, now: now)
        if let existing = entries[gram] {
          entries[gram] = Entry(c: max(existing.c, entry.c), t: max(existing.t, entry.t))
        } else {
          entries[gram] = entry
        }
      }
    }
    // 跨詞的接續不要：接續的第一個字跟上文黏得比跟下一個字更緊（「我」→「們今」：「我們」遠比「們今」常見）
    let lastText = String(last)
    entries = entries.filter { gram, _ in
      guard gram.count >= 2 else { return true }
      let chars = Array(gram)
      let withContext = snapshot.words[lastText + String(chars[0])]?.c ?? 0
      let inside = snapshot.words[String(chars[0 ... 1])]?.c ?? 0
      return withContext <= inside * 1.2
    }
    let kept = Set(Self.preferShortContinuations(entries.map { ($0.key, $0.value) }).map { $0.0 })
    return scores
      .filter { kept.contains($0.key) }
      .map { ($0.key, $0.key.count >= 2 ? $0.value * 1.3 : $0.value) }
      .sorted { $0.1 > $1.1 }
      .prefix(limit)
      .map { $0.0 }
  }

  // MARK: - 整理

  private func prune() {
    let now = Date().timeIntervalSince1970
    if snapshot.words.count > Self.maxWords {
      let keep = snapshot.words
        .sorted { Self.score($0.value, now: now) > Self.score($1.value, now: now) }
        .prefix(Self.maxWords * 4 / 5)
      snapshot.words = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
    for (key, map) in snapshot.follows where map.count > Self.maxFollowsPerKey {
      let keep = map.sorted { Self.score($0.value, now: now) > Self.score($1.value, now: now) }
        .prefix(Self.maxFollowsPerKey)
      snapshot.follows[key] = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
    if snapshot.follows.count > Self.maxFollowKeys {
      let keep = snapshot.follows
        .map { key, map in (key, map, map.values.map { Self.score($0, now: now) }.reduce(0, +)) }
        .sorted { $0.2 > $1.2 }
        .prefix(Self.maxFollowKeys * 4 / 5)
      snapshot.follows = Dictionary(uniqueKeysWithValues: keep.map { ($0.0, $0.1) })
    }
  }

  // MARK: - 工具

  static func isHan(_ ch: Character) -> Bool {
    guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
    if scalar == "〇" { return true }
    return scalar.properties.isIdeographic && scalar.value >= 0x3400
  }
}
