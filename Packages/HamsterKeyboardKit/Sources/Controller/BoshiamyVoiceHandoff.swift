//
//  BoshiamyVoiceHandoff.swift
//  HamsterKeyboardKit
//
//  Gary fork：iOS 不允許自訂鍵盤錄音（AVAudioEngine.start 回 'what' 2003329396），
//  所以語音改由主 App 錄音辨識：鍵盤按語音鍵 → 打開主 App 的語音頁 → 辨識結果存到
//  App Group → 使用者點左上角「◀」回到原本的 App → 鍵盤重新出現時把文字送出。
//

import Foundation
import HamsterKit

public enum BoshiamyVoiceHandoff {
  /// 主 App 語音頁的 URL（SceneDelegate 以 lastPathComponent == "voice" 判斷）
  public static let voiceURL = URL(string: "hamster://dev.fuxiao.app.hamster/voice")!

  public static let voicePathComponent = "voice"

  private static let textKey = "boshiamy.voice.pendingText"
  private static let dateKey = "boshiamy.voice.pendingDate"

  /// 超過這個時間還沒被鍵盤取走的文字就丟掉，避免很久以後突然冒出來
  private static let maxAge: TimeInterval = 10 * 60

  /// 主 App：存下要交給鍵盤的文字
  public static func save(_ text: String) {
    UserDefaults.hamster.set(text, forKey: textKey)
    UserDefaults.hamster.set(Date().timeIntervalSince1970, forKey: dateKey)
    UserDefaults.hamster.synchronize()
    FileManager.hamsterDiag("[voice] handoff saved: \(text.prefix(12))")
  }

  /// 鍵盤：取出待送出的文字（取出後即清除）；沒有或過期回傳 nil
  public static func take() -> String? {
    guard let text = UserDefaults.hamster.string(forKey: textKey) else { return nil }
    let savedAt = UserDefaults.hamster.double(forKey: dateKey)
    UserDefaults.hamster.removeObject(forKey: textKey)
    UserDefaults.hamster.removeObject(forKey: dateKey)
    UserDefaults.hamster.synchronize()
    guard !text.isEmpty, Date().timeIntervalSince1970 - savedAt <= maxAge else {
      FileManager.hamsterDiag("[voice] handoff dropped (empty or expired)")
      return nil
    }
    return text
  }
}
