//
//  VirtualJoystick.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import UIKit

class VirtualJoystick: UIView {
    var onDirectionChanged: ((CGPoint) -> Void)?
    var onReleased: (() -> Void)?
    
    private let baseView = UIView()
    private let stickView = UIView()
    private var isTracking = false
    private let stickRadius: CGFloat = 30
    private let baseRadius: CGFloat = 60
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupJoystick()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupJoystick()
    }
    
    private func setupJoystick() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        
        // Base circle
        baseView.backgroundColor = UIColor(white: 1.0, alpha: 0.2)
        baseView.layer.cornerRadius = baseRadius
        baseView.layer.borderWidth = 2
        baseView.layer.borderColor = UIColor(white: 1.0, alpha: 0.4).cgColor
        addSubview(baseView)
        
        // Stick circle
        stickView.backgroundColor = UIColor(white: 1.0, alpha: 0.4)
        stickView.layer.cornerRadius = stickRadius
        stickView.layer.borderWidth = 2
        stickView.layer.borderColor = UIColor(white: 1.0, alpha: 0.6).cgColor
        addSubview(stickView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        
        baseView.frame = CGRect(
            x: center.x - baseRadius,
            y: center.y - baseRadius,
            width: baseRadius * 2,
            height: baseRadius * 2
        )
        
        if !isTracking {
            stickView.frame = CGRect(
                x: center.x - stickRadius,
                y: center.y - stickRadius,
                width: stickRadius * 2,
                height: stickRadius * 2
            )
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        // Check if touch is within joystick area
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let distance = sqrt(pow(location.x - center.x, 2) + pow(location.y - center.y, 2))
        
        if distance <= baseRadius * 2 {
            isTracking = true
            updateStickPosition(location: location)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTracking, let touch = touches.first else { return }
        let location = touch.location(in: self)
        updateStickPosition(location: location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTracking = false
        resetStick()
        onReleased?()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTracking = false
        resetStick()
        onReleased?()
    }
    
    private func updateStickPosition(location: CGPoint) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var dx = location.x - center.x
        var dy = location.y - center.y
        
        let distance = sqrt(dx * dx + dy * dy)
        let maxDistance = baseRadius - stickRadius
        
        if distance > maxDistance {
            let angle = atan2(dy, dx)
            dx = cos(angle) * maxDistance
            dy = sin(angle) * maxDistance
        }
        
        stickView.center = CGPoint(x: center.x + dx, y: center.y + dy)
        
        // Normalize direction (-1 to 1)
        let normalizedX = dx / maxDistance
        let normalizedY = -dy / maxDistance  // Invert Y for game coordinates
        
        onDirectionChanged?(CGPoint(x: normalizedX, y: normalizedY))
    }
    
    private func resetStick() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        UIView.animate(withDuration: 0.2) {
            self.stickView.center = center
        }
        onDirectionChanged?(CGPoint.zero)
    }
    
    func getDirection() -> CGPoint {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let stickCenter = stickView.center
        let dx = stickCenter.x - center.x
        let dy = stickCenter.y - center.y
        let maxDistance = baseRadius - stickRadius
        
        if maxDistance > 0 {
            return CGPoint(x: dx / maxDistance, y: -dy / maxDistance)
        }
        return CGPoint.zero
    }
}

