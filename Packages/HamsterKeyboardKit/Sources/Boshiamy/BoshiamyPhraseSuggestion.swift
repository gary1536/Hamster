//
//  BoshiamyPhraseSuggestion.swift
//  HamsterKeyboardKit
//
//  Gary fork：候選列（沒在打字時）的「常用詞」。
//
//  - 平常候選列中間保持空白，不主動顯示常用詞（2026-11-07 使用者要求，Android 1.1.0-5 同步）。
//  - 剛上屏一個字或詞後，顯示以它開頭／常接在它後面的「使用者自己的」常用詞（只用本機統計，不用詞庫補）。
//    顯示整個詞（上屏「永」→ 顯示「永盈」），點選時只送出後面還沒上屏的部分（「盈」）。
//  - 按其他任何鍵、或開始打新字根，就消失。
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

  /// 與 items 對應：點選時實際要上屏的文字（去掉已經上屏的開頭）
  private var commitTexts: [String] = []

  /// 最近一次上屏的詞（顯示時當作開頭），只取結尾的漢字，最多 4 個
  private var anchor = ""

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
    commit(text, anchorWord: text)
  }

  /// 使用者點了候選列第 index 個詞：只送出還沒上屏的部分，下次聯想以整個詞當開頭
  public func select(at index: Int) {
    guard index >= 0, index < commitTexts.count, index < items.count else { return }
    let text = commitTexts[index]
    let word = items[index]
    insertHandler?(text)
    commit(text, anchorWord: word)
  }

  private func commit(_ text: String, anchorWord: String) {
    guard canRecord else { return }
    store.record(text)
    anchor = Self.trailingHan(anchorWord)
    showAssociations()
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

  /// 沒剛上屏：候選列中間保持空白
  private func showCommon() {
    mode = .common
    commitTexts = []
    if !items.isEmpty { items = [] }
  }

  private func showAssociations() {
    let context = store.currentContext
    guard canRecord, !context.isEmpty else {
      showCommon()
      return
    }
    let continuations = convertForDisplay(store.userAssociations(after: context, limit: Self.maxItems))
    if continuations.isEmpty {
      showCommon()
      return
    }
    // 顯示的開頭：剛上屏的詞（要以上文結尾，否則只用上文）
    let prefix = (!anchor.isEmpty && anchor.hasSuffix(context)) ? anchor : context
    mode = .association
    commitTexts = continuations
    items = continuations.map { prefix + $0 }
  }

  /// 文字結尾連續的漢字，最多 4 個
  private static func trailingHan(_ text: String) -> String {
    var chars: [Character] = []
    for ch in text.reversed() {
      guard chars.count < 4, BoshiamyPhraseStore.isHan(ch) else { break }
      chars.insert(ch, at: 0)
    }
    return String(chars)
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
