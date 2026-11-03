//
//  VoiceModule.swift
//  HamsterKeyboardKit
//
//  語音輸入模組（M0）：AVAudioEngine + SFSpeechRecognizer（zh-TW）。
//  - 線上辨識為主；裝置若支援繁體離線辨識（supportsOnDeviceRecognition）自動改用離線。
//  - 需「允許完整取用」才能走網路；無權限時以 onError 提示。
//  - 辨識結果由外部 onFinalResult 決定如何上屏（鍵盤擴充直接 textDocumentProxy.insertText）。
//

import AVFoundation
import Foundation
import OpenCCBridge
import Speech

public final class VoiceModule: NSObject {
  public enum State {
    case idle
    case listening
  }

  public private(set) var state: State = .idle

  /// 最終辨識文字（一句話結束或手動停止時回傳）
  public var onFinalResult: ((String) -> Void)?
  /// 部分辨識結果（可用來即時顯示）
  public var onPartialResult: ((String) -> Void)?
  /// 錯誤訊息（權限拒絕、引擎不可用等）
  public var onError: ((String) -> Void)?

  public static let stateDidChangeNotification = Notification.Name("HamsterVoiceStateDidChange")

  private let audioEngine = AVAudioEngine()
  private lazy var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-TW"))
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  // MARK: - 簡轉繁（OpenCC s2t）

  /// Apple 雲端 zh-TW 辨識仍常回簡體，上屏前用 OpenCC 強制轉繁。
  /// 資料檔隨 SharedSupport.zip 部署在 App Group：.../opencc/s2t.json
  private lazy var openccHandle: opencc_t? = {
    let configURL = FileManager.appGroupSharedSupportDirectoryURL
      .appendingPathComponent("opencc", isDirectory: true)
      .appendingPathComponent("s2t.json")
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      return nil
    }
    let handle = configURL.path.withCString { opencc_open($0) }
    if handle == UnsafeMutableRawPointer(bitPattern: -1) {
      return nil
    }
    return handle
  }()

  func toTraditional(_ text: String) -> String {
    guard let handle = openccHandle else { return text }
    let converted: String = text.withCString { cString in
      guard let out = opencc_convert_utf8(handle, cString, strlen(cString)) else {
        return text
      }
      defer { opencc_convert_utf8_free(out) }
      return String(cString: out)
    }
    return converted
  }

  // MARK: - Public

  /// 切換：未在聽 → 開始；正在聽 → 停止並提交
  public func toggle() {
    if state == .listening {
      stop()
    } else {
      start()
    }
  }

  public func start() {
    guard state == .idle else { return }
    SFSpeechRecognizer.requestAuthorization { auth in
      guard auth == .authorized else {
        DispatchQueue.main.async { [weak self] in
          self?.onError?("請在「設定→隱私→語音辨識」開啟權限")
        }
        return
      }
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        guard granted else {
          DispatchQueue.main.async { [weak self] in
            self?.onError?("請在「設定→隱私→麥克風」開啟權限（鍵盤需同時開啟允許完整取用）")
          }
          return
        }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          do {
            try self.begin()
          } catch {
            self.onError?("無法開始錄音：\(error.localizedDescription)")
          }
        }
      }
    }
  }

  public func stop() {
    guard task != nil || state == .listening else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    if audioEngine.isRunning { audioEngine.stop() }
    request?.endAudio()
    task?.finish()
    task = nil
    request = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    setState(.idle)
  }

  // MARK: - Private

  private func begin() throws {
    guard let recognizer, recognizer.isAvailable else {
      onError?("此裝置目前無法使用繁體中文語音辨識")
      return
    }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    // 2026-11-04 修正：不強制離線辨識——Apple 離線中文模型輸出簡體；
    // 雲端 zh-TW 辨識（需允許完整取用）才回繁體。Gary 要繁體輸出。
    request = req

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      onError?("找不到可用的麥克風輸入")
      return
    }
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
      req?.append(buffer)
    }
    audioEngine.prepare()
    try audioEngine.start()

    setState(.listening)

    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let text = result.bestTranscription.formattedString
        let isFinal = result.isFinal
        DispatchQueue.main.async {
          if isFinal {
            self.onFinalResult?(self.toTraditional(text))
            self.stop()
          } else {
            self.onPartialResult?(text)
          }
        }
      } else if error != nil {
        // 取消/超時等：靜默停止（已收到的 partial 不強制上屏）
        DispatchQueue.main.async { [weak self] in
          self?.stop()
        }
      }
    }
  }

  private func setState(_ newState: State) {
    guard state != newState else { return }
    state = newState
    NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
  }
}
