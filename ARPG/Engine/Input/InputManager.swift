//
//  InputManager.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import UIKit
import simd

class InputManager {
    static let shared = InputManager()
    
    // Movement input (normalized -1 to 1)
    var moveDirection: SIMD2<Float> = SIMD2<Float>(0, 0)
    
    // Action states
    var isAttackPressed: Bool = false
    var isJumpPressed: Bool = false
    var isActionPressed: Bool = false
    var isSkill1Pressed: Bool = false
    var isSkill2Pressed: Bool = false
    var isSkill3Pressed: Bool = false
    var isSkill4Pressed: Bool = false  // Ult
    
    private init() {}
    
    func updateMoveDirection(_ direction: CGPoint) {
        moveDirection = SIMD2<Float>(Float(direction.x), Float(direction.y))
    }
    
    func resetMoveDirection() {
        moveDirection = SIMD2<Float>(0, 0)
    }
}

