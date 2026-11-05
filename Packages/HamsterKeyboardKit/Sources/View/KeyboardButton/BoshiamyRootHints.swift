//
//  BoshiamyRootHints.swift
//
//  嘸蝦米鍵帽字根提示：中文 26 鍵右下角顯示該鍵的代表字根。
//  字根以 boshiamy.dict.yaml 核對（部首字的第一碼即其所在鍵）。
//

import Foundation

enum BoshiamyRootHints {
  static let roots: [String: String] = [
    "a": "金", "b": "人八", "c": "虫車", "d": "刀日", "e": "山酉",
    "f": "火方", "g": "女甘", "h": "手心", "i": "言工", "j": "十",
    "k": "王斤", "l": "立石", "m": "目門", "n": "鳥巾", "o": "口",
    "p": "卜白", "q": "田弓", "r": "耳儿", "s": "小糸", "t": "木",
    "u": "月雨", "v": "隹", "w": "水文", "x": "食氏", "y": "土",
    "z": "竹子",
  ]

  static func hint(for action: KeyboardAction) -> String? {
    guard case .character(let char) = action else { return nil }
    return roots[char.lowercased()]
  }
}
