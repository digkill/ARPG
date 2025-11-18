//
//  ActionButton.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import UIKit

class ActionButton: UIButton {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    
    private var isPressed = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }
    
    private func setupButton() {
        backgroundColor = UIColor(white: 1.0, alpha: 0.2)
        layer.cornerRadius = 25
        layer.borderWidth = 2
        layer.borderColor = UIColor(white: 1.0, alpha: 0.4).cgColor
        
        setTitleColor(.white, for: .normal)
        titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel?.textAlignment = .center
        
        addTarget(self, action: #selector(buttonPressed), for: .touchDown)
        addTarget(self, action: #selector(buttonReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func buttonPressed() {
        if !isPressed {
            isPressed = true
            UIView.animate(withDuration: 0.1) {
                self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                self.backgroundColor = UIColor(white: 1.0, alpha: 0.4)
            }
            onPressed?()
        }
    }
    
    @objc private func buttonReleased() {
        if isPressed {
            isPressed = false
            UIView.animate(withDuration: 0.1) {
                self.transform = .identity
                self.backgroundColor = UIColor(white: 1.0, alpha: 0.2)
            }
            onReleased?()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure button stays circular
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}

