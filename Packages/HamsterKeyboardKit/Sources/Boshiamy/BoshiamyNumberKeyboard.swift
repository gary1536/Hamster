//
//  BoshiamyNumberKeyboard.swift
//  HamsterKeyboardKit
//
//  Gary fork：嘸蝦米的數字鍵盤（與 Android 版 Trime 的 5 欄數字鍵盤相同，PLAN.md 第 10 節）。
//
//  - 寫在程式裡，不放 hamster.yaml：yaml 只在第一次安裝或「RIME 重置」時套用，已安裝的設定吃不到。
//  - 數字與符號用 .symbol 直接上屏（半形），不經過 RIME，所以 `.` `,` 不會被當成嘸蝦米字根。
//    也不動 RIME 的 ascii_mode，回嘸蝦米鍵盤後繁／簡、中／英維持原樣。
//  - 「返回」「嘸蝦米」兩個鍵都回到嘸蝦米鍵盤（returnLastKeyboard）。
//  - 5 列，每列高度是標準列高的 4/5，整個鍵盤高度與 4 列的嘸蝦米鍵盤相同（CustomizeKeyboardProvider）。
//

import UIKit

public enum BoshiamyNumberKeyboard {
  public static let name = "嘸蝦米數字"

  public static var keyboardType: KeyboardType { .custom(named: name) }

  public static func isNumberKeyboard(_ type: KeyboardType) -> Bool {
    if case .custom(let named, _) = type { return named == name }
    return false
  }

  public static let keyboard: Keyboard = {
    let width = KeyWidth(portrait: .percentage(0.2), landscape: .percentage(0.2))
    func symbol(_ char: String) -> Key {
      Key(action: .symbol(Symbol(char: char)), width: width, label: KeyLabel(text: char), processByRIME: false)
    }
    func back(_ label: String) -> Key {
      Key(action: .returnLastKeyboard, width: width, label: KeyLabel(text: label), processByRIME: false)
    }
    let rows: [[Key]] = [
      ["+", "1", "2", "3", "#"].map(symbol),
      ["-", "4", "5", "6", "%"].map(symbol),
      ["*", "7", "8", "9", ":"].map(symbol),
      ["/", "±", "0", ".", ","].map(symbol),
      [
        symbol("="),
        back("返回"),
        back("嘸蝦米"),
        Key(action: .backspace, width: width, processByRIME: false),
        Key(action: .primary(.return), width: width, processByRIME: false),
      ],
    ]
    return Keyboard(name: name, type: keyboardType, isPrimary: false, rows: rows.map { Row(keys: $0) })
  }()
}
