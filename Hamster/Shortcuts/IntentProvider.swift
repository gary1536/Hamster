//
//  IntentProvider.swift
//  Hamster
//
//  Created by morse on 2023/9/25.
//

import AppIntents

@available(iOS 16.0, *)
struct IntentProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    return [
      AppShortcut(intent: RimeSyncIntent(), phrases: ["Sync RIME in \(.applicationName)", "在\(.applicationName)同步 RIME"]),
      AppShortcut(intent: RimeDeployIntent(), phrases: ["Deploy RIME in \(.applicationName)", "在\(.applicationName)重新部署 RIME"]),
    ]
  }
}
