//
//  GameModels.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//

import Foundation
import simd

enum WorldConstants {
    static let groundY: Float = 0.0
    static let mapHalfSize: Float = 45.0
    static let heroPlatformRadius: Float = 1.4
}

struct CharacterInstance {
    var position: SIMD3<Float>
    var rotation: Float
    var velocity: SIMD3<Float>
    var scale: Float
    var lastStepTime: Float
}

struct DecorativeObject {
    var position: SIMD3<Float>
    var scale: Float
}

struct MinimapState {
    var hero: SIMD2<Float>?
    var heroRotation: Float?
    var objects: [SIMD2<Float>]
    var halfSize: Float
}

struct Ability {
    let name: String
    let manaCost: Float
    let cooldown: Float
    var currentCooldown: Float
    let castRange: Float
}

enum AbilityKey: CaseIterable {
    case qAvalanche
    case wToss
    case eTreeGrab
    case rGrow
    // Abyssus abilities
    case qRiftCleaver
    case wAbyssalChains
    case eVoidplateResonance
    case rRuptureOfTheVoid
}

struct HeroStats {
    var level: Int = 1
    var maxHealth: Float = 600
    var health: Float = 600
    var maxMana: Float = 300
    var mana: Float = 300
    var strength: Float = 22
    var agility: Float = 10
    var intelligence: Float = 14
    var baseDamage: Float = 50
    var attackRange: Float = 2.5
    var hasTree: Bool = false
    var treeBonusDamage: Float = 0
    var growMultiplier: Float = 1
}

enum ItemType: Int {
    case empty = 0
    case tango = 1
    case clarity = 2
    case ironBranch = 3
    case faerieFire = 4
    
    var name: String {
        switch self {
        case .tango: return "Tango"
        case .clarity: return "Clarity"
        case .ironBranch: return "Iron Branch"
        case .faerieFire: return "Faerie Fire"
        case .empty: return "Empty"
        }
    }
    
    var cooldown: Float {
        switch self {
        case .tango: return 60.0
        case .clarity: return 30.0
        default: return 0.0
        }
    }
    
    var effectDescription: String {
        switch self {
        case .tango: return "Heals 115 HP over time"
        case .clarity: return "Restores 100 mana over time"
        case .ironBranch: return "Passive: +1 all stats"
        case .faerieFire: return "Consumable: +100 HP"
        case .empty: return ""
        }
    }
    
    func applyEffect(to stats: inout HeroStats) {
        switch self {
        case .tango:
            stats.health = min(stats.maxHealth, stats.health + 115)
        case .clarity:
            stats.mana = min(stats.maxMana, stats.mana + 100)
        case .faerieFire:
            stats.health = min(stats.maxHealth, stats.health + 100)
        case .ironBranch:
            stats.strength += 1
            stats.agility += 1
            stats.intelligence += 1
        case .empty:
            break
        }
    }
}

struct ItemSlot {
    var type: ItemType = .empty
    var count: Int = 0
    var cooldown: Float = 0.0
    
    var maxCooldown: Float {
        type.cooldown
    }
    
    var isOnCooldown: Bool {
        cooldown > 0
    }
    
    var isEmpty: Bool {
        type == .empty || count == 0
    }
}
