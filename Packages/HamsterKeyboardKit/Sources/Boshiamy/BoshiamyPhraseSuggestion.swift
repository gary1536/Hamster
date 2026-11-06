//
//  BoshiamyPhraseSuggestion.swift
//  HamsterKeyboardKit
//
//  Gary fork：候選列（沒在打字時）的「常用詞」與「聯想」。
//
//  - 平常顯示常用詞（BoshiamyPhraseStore.commonPhrases）。
//  - 剛上屏後顯示聯想：先用使用者自己的接續統計，不足時用 boshiamy_assoc.txt（rime-essay 詞頻產生）補。
//  - 按其他任何鍵就回到常用詞。
//  - 打繁出簡模式：顯示與上屏的詞用 OpenCC t2s 轉成簡體。
//  - 密碼欄位、secure text、或設定關閉時：不記錄也不顯示。
//

import Combine
import Foundation
import HamsterKit
import OpenCCBridge

public final class BoshiamyPhraseSuggestion: ObservableObject {
  public enum Mode {
    case common
    case association
  }

  /// 候選列中間要顯示的詞
  @Published public private(set) var items: [String] = []
  @Published public private(set) var mode: Mode = .common

  /// 設定「常用詞與聯想」
  public var enabled = true {
    didSet { if oldValue != enabled { refresh() } }
  }

  /// 目前輸入框是密碼或 secure text
  public var isSecureContext = false {
    didSet { if oldValue != isSecureContext { refresh() } }
  }

  /// 打繁出簡模式（由 RimeContext 的 boshiamySimplified 同步）
  public var simplified = false {
    didSet { if oldValue != simplified { refresh() } }
  }

  /// 點選候選列的詞時，由鍵盤 controller 實際送進輸入框
  public var insertHandler: ((String) -> Void)?

  public static let maxItems = 10

  private let store = BoshiamyPhraseStore.shared
  private var canRecord: Bool { enabled && !isSecureContext }

  public init() {}

  // MARK: - 事件

  /// 鍵盤出現
  public func keyboardWillAppear() {
    store.reloadIfNeeded()
    store.breakContext()
    showCommon()
  }

  /// 鍵盤消失
  public func keyboardWillDisappear() {
    store.saveNow()
  }

  /// RIME 或候選列送出了文字
  public func didCommit(_ text: String) {
    guard canRecord else { return }
    store.record(text)
    showAssociations()
  }

  /// 使用者點了候選列的詞
  public func select(_ text: String) {
    insertHandler?(text)
    didCommit(text)
  }

  /// 按了鍵盤上的任何鍵：聯想消失。
  /// 送進 RIME 的字母鍵不切斷連續段（之後的上屏接在後面）；其他鍵（刪除、空白、Enter、符號…）會切斷。
  public func keyPressed(continuesText: Bool) {
    if !continuesText {
      store.breakContext()
    }
    if mode != .common {
      showCommon()
    }
  }

  /// 輸入框內容被外部改動（游標移動、換欄位）
  public func contextDidChange() {
    store.breakContext()
    if mode != .common {
      showCommon()
    }
  }

  public func refresh() {
    if mode == .association {
      showAssociations()
    } else {
      showCommon()
    }
  }

  // MARK: - 產生清單

  private func showCommon() {
    mode = .common
    guard canRecord else {
      items = []
      return
    }
    items = convertForDisplay(store.commonPhrases(limit: Self.maxItems))
  }

  private func showAssociations() {
    let context = store.currentContext
    guard canRecord, !context.isEmpty else {
      showCommon()
      return
    }
    var result = convertForDisplay(store.userAssociations(after: context, limit: Self.maxItems))
    if result.count < Self.maxItems {
      for word in dictionaryAssociations(after: context) where !result.contains(word) {
        result.append(word)
        if result.count >= Self.maxItems { break }
      }
    }
    if result.isEmpty {
      showCommon()
      return
    }
    mode = .association
    items = result
  }

  // MARK: - 詞庫補詞（boshiamy_assoc.txt）

  private lazy var dictionary: [Character: [String]] = {
    guard let url = Bundle.module.url(forResource: "boshiamy_assoc", withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      FileManager.hamsterDiag("[phrase] boshiamy_assoc.txt not found")
      return [:]
    }
    var map: [Character: [String]] = [:]
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: "\t").map(String.init)
      guard let lead = parts.first?.first, parts.count > 1 else { continue }
      map[lead] = Array(parts.dropFirst())
    }
    return map
  }()

  private func dictionaryAssociations(after context: String) -> [String] {
    guard let last = context.last else { return [] }
    if simplified {
      // 詞庫是繁體：上文先轉繁體查，結果再轉簡體
      let traditionalLast = convert(String(last), handle: s2tHandle).first ?? last
      let words = dictionary[traditionalLast] ?? dictionary[last] ?? []
      return words.map { convert($0, handle: t2sHandle) }
    }
    return dictionary[last] ?? []
  }

  // MARK: - OpenCC

  private func convertForDisplay(_ words: [String]) -> [String] {
    guard simplified else { return words }
    var seen = Set<String>()
    return words.map { convert($0, handle: t2sHandle) }.filter { seen.insert($0).inserted }
  }

  private var _t2s: opencc_t?
  private var _s2t: opencc_t?

  private var t2sHandle: opencc_t? {
    if _t2s == nil { _t2s = Self.openOpenCC("t2s.json") }
    return _t2s
  }

  private var s2tHandle: opencc_t? {
    if _s2t == nil { _s2t = Self.openOpenCC("s2t.json") }
    return _s2t
  }

  private static func openOpenCC(_ name: String) -> opencc_t? {
    let url = FileManager.appGroupSharedSupportDirectoryURL
      .appendingPathComponent("opencc", isDirectory: true)
      .appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let handle = url.path.withCString { opencc_open($0) }
    if handle == nil || handle == UnsafeMutableRawPointer(bitPattern: -1) { return nil }
    return handle
  }

  private func convert(_ text: String, handle: opencc_t?) -> String {
    guard let handle else { return text }
    return text.withCString { cString in
      guard let out = opencc_convert_utf8(handle, cString, strlen(cString)) else { return text }
      defer { opencc_convert_utf8_free(out) }
      return String(cString: out)
    }
  }
}
