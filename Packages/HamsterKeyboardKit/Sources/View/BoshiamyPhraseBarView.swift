//
//  BoshiamyPhraseBarView.swift
//  HamsterKeyboardKit
//
//  Gary fork：候選列中間的「常用詞／聯想」橫列，可左右捲動，點一下直接上屏。
//

import UIKit

final class BoshiamyPhraseBarView: UIView {
  var onSelect: ((String) -> Void)?

  private var textColor: UIColor
  private var pressedColor: UIColor
  private let font: UIFont

  private lazy var scrollView: UIScrollView = {
    let view = UIScrollView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.showsHorizontalScrollIndicator = false
    view.showsVerticalScrollIndicator = false
    view.alwaysBounceHorizontal = true
    view.delaysContentTouches = false
    return view
  }()

  private lazy var stackView: UIStackView = {
    let view = UIStackView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.axis = .horizontal
    view.alignment = .fill
    view.spacing = 2
    return view
  }()

  init(textColor: UIColor, pressedColor: UIColor, font: UIFont) {
    self.textColor = textColor
    self.pressedColor = pressedColor
    self.font = font
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(scrollView)
    scrollView.addSubview(stackView)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setColors(textColor: UIColor, pressedColor: UIColor) {
    self.textColor = textColor
    self.pressedColor = pressedColor
    for case let button as UIButton in stackView.arrangedSubviews {
      button.setTitleColor(textColor, for: .normal)
    }
  }

  func update(_ items: [String]) {
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for item in items {
      let button = UIButton(type: .custom)
      button.setTitle(item, for: .normal)
      button.titleLabel?.font = font
      button.setTitleColor(textColor, for: .normal)
      button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
      button.layer.cornerRadius = 6
      button.addTarget(self, action: #selector(touchDown(_:)), for: .touchDown)
      button.addTarget(self, action: #selector(touchUp(_:)), for: .touchUpInside)
      button.addTarget(self, action: #selector(touchCancel(_:)), for: [.touchUpOutside, .touchCancel])
      stackView.addArrangedSubview(button)
    }
    scrollView.setContentOffset(.zero, animated: false)
  }

  @objc private func touchDown(_ sender: UIButton) {
    sender.backgroundColor = pressedColor
  }

  @objc private func touchCancel(_ sender: UIButton) {
    sender.backgroundColor = .clear
  }

  @objc private func touchUp(_ sender: UIButton) {
    sender.backgroundColor = .clear
    guard let text = sender.title(for: .normal), !text.isEmpty else { return }
    onSelect?(text)
  }
}
