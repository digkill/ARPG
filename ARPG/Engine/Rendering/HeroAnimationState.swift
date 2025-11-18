//
//  HeroAnimationState.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//

import Foundation

enum HeroAnimationState: CaseIterable {
    case idle
    case walking
    case attacking
    case takingDamage
    case dead
    case usingSkill
    case usingSpecialSkill
}
