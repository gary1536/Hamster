//
//  VoiceCaptureViewController.swift
//  HamsteriOS
//
//  Gary fork：主 App 的語音輸入頁。鍵盤不能錄音，按語音鍵時會打開這一頁：
//  自動開始聆聽 → 按「完成」→ 依鍵盤目前的繁簡模式轉換後存到 App Group →
//  使用者點左上角「◀」回到原本的 App，鍵盤會自動送出文字。
//

import AVFoundation
import HamsterKeyboardKit
import HamsterKit
import Speech
import UIKit

public final class VoiceCaptureViewController: UIViewController {
  private let voice = VoiceModule()

  /// 最近一次的部分辨識結果（沒有收到最終結果時用它）
  private var lastPartial = ""

  /// 已經按了「完成」，等待最終結果
  private var finishing = false

  /// 這一輪已經存好交給鍵盤
  private var delivered = false

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.text = "嘸蝦米語音輸入"
    label.font = .systemFont(ofSize: 22, weight: .semibold)
    label.textAlignment = .center
    return label
  }()

  private let statusLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 16)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()

  private let transcriptLabel: UILabel = {
    let label = UILabel()
    label.font = .systemFont(ofSize: 26)
    label.textAlignment = .center
    label.numberOfLines = 0
    return label
  }()

  private lazy var doneButton: UIButton = makeButton(title: "完成", filled: true, action: #selector(doneTapped))
  private lazy var retryButton: UIButton = makeButton(title: "再說一次", filled: false, action: #selector(retryTapped))
  private lazy var closeButton: UIButton = makeButton(title: "取消", filled: false, action: #selector(closeTapped))

  override public func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    let buttons = UIStackView(arrangedSubviews: [doneButton, retryButton, closeButton])
    buttons.axis = .vertical
    buttons.spacing = 12

    let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, transcriptLabel, buttons])
    stack.axis = .vertical
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      doneButton.heightAnchor.constraint(equalToConstant: 52),
      retryButton.heightAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),
    ])

    voice.onPartialResult = { [weak self] text in
      guard let self else { return }
      self.lastPartial = text
      // 即時文字也照目前的繁簡模式顯示，和最後送出的一致
      self.transcriptLabel.text = self.voice.convertForOutput(text)
    }
    voice.onFinalResult = { [weak self] text in
      self?.deliver(text)
    }
    voice.onError = { [weak self] message in
      guard let self else { return }
      FileManager.hamsterDiag("[app voice] error: \(message)")
      // 已經按了完成，錯誤（例如沒說話）時用部分結果
      if self.finishing {
        self.deliverPartialIfAny()
        return
      }
      self.statusLabel.text = message
      self.setButtons(listening: false)
    }
  }

  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startListening()
  }

  override public func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    voice.stop()
  }

  // MARK: - 流程

  private func startListening() {
    lastPartial = ""
    finishing = false
    delivered = false
    transcriptLabel.text = ""

    let speech = SFSpeechRecognizer.authorizationStatus()
    let mic = AVCaptureDevice.authorizationStatus(for: .audio)
    if speech == .notDetermined || mic == .notDetermined {
      statusLabel.text = "請允許麥克風與語音辨識"
      requestPermissions { [weak self] in self?.startListening() }
      return
    }
    guard speech == .authorized, mic == .authorized else {
      statusLabel.text = "請到「設定 → 嘸蝦米」開啟麥克風與語音辨識"
      setButtons(listening: false)
      return
    }

    statusLabel.text = "正在聆聽，請說話……說完按「完成」"
    setButtons(listening: true)
    voice.start()
  }

  private func requestPermissions(then next: @escaping () -> Void) {
    SFSpeechRecognizer.requestAuthorization { _ in
      AVCaptureDevice.requestAccess(for: .audio) { _ in
        DispatchQueue.main.async { next() }
      }
    }
  }

  @objc private func doneTapped() {
    guard !finishing else { return }
    finishing = true
    statusLabel.text = "辨識中……"
    doneButton.isEnabled = false
    voice.stop()
    // 最終結果通常很快就回來；沒有的話就用最後一次的部分結果
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
      self?.deliverPartialIfAny()
    }
  }

  @objc private func retryTapped() {
    voice.stop()
    startListening()
  }

  @objc private func closeTapped() {
    voice.stop()
    dismiss(animated: true)
  }

  private func deliverPartialIfAny() {
    guard !delivered else { return }
    if lastPartial.isEmpty {
      statusLabel.text = "沒有聽到內容，請按「再說一次」"
      setButtons(listening: false)
      return
    }
    deliver(voice.convertForOutput(lastPartial))
  }

  /// 存到 App Group，等鍵盤重新出現時送出
  private func deliver(_ text: String) {
    guard !delivered, !text.isEmpty else { return }
    delivered = true
    BoshiamyVoiceHandoff.save(text)
    transcriptLabel.text = text
    statusLabel.text = "完成！請點左上角「◀」返回原本的 App，文字會自動送出"
    setButtons(listening: false)
  }

  private func setButtons(listening: Bool) {
    doneButton.isHidden = !listening
    doneButton.isEnabled = listening
    retryButton.isHidden = listening
  }

  private func makeButton(title: String, filled: Bool, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 18, weight: filled ? .semibold : .regular)
    if filled {
      button.backgroundColor = .systemBlue
      button.setTitleColor(.white, for: .normal)
      button.layer.cornerRadius = 12
    }
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }
}
