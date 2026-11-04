//
//  AppDelegete.swift
//  Hamster
//
//  Created by morse on 2023/6/5.
//

import AVFoundation
import HamsterKit
import Speech
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // 自愈（Gary fork v2）：不依賴 lazy 單例，在啟動最早點直接補同步詞庫
    FileManager.repairAppGroupFromSandboxIfNeeded()
    // Gary fork：沙箱的 prism 若是壞的（Darts ODR 衝突），換成預編檔後同步給鍵盤
    if !FileManager.repairBrokenPrisms().isEmpty {
      try? FileManager.syncSandboxUserDataDirectoryToAppGroup(override: true)
      UserDefaults.hamster.overrideRimeDirectory = true
    }
    requestVoicePermissionsIfNeeded()
    return true
  }

  /// Gary fork：鍵盤擴充不能跳出權限詢問（一詢問 iOS 就終止鍵盤、退回上一個鍵盤），
  /// 所以由主 App 詢問麥克風與語音辨識權限。
  private func requestVoicePermissionsIfNeeded() {
    if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
      SFSpeechRecognizer.requestAuthorization { status in
        FileManager.hamsterDiag("[app] speech authorization=\(status.rawValue)")
      }
    }
    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        FileManager.hamsterDiag("[app] microphone granted=\(granted)")
      }
    }
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }
}
