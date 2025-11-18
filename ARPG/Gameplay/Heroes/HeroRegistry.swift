//
//  HeroRegistry.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//

import Foundation

struct HeroDefinition: Equatable {
    let identifier: String
    let displayName: String
    let modelPath: String
    let bundleSubdirectory: String
    let scale: Float
    // Угол наклона модели (в радианах) - может быть разным для каждой модели
    // Например: 0 - без поворота, Float.pi / 2 - 90 градусов вверх
    let rotation: SIMD4<Float> // (x, y, z, angle) - ось и угол поворота
    // Маппинг стандартных имен анимаций на реальные имена в модели
    // Например: walk -> "Walking", idle -> "Combat Idle"
    let animationMap: [HeroAnimationState: String]
    // Маппинг путей к отдельным файлам анимаций (если каждая анимация в отдельном файле)
    // Например: для Abyssus: [.idle: "Abyssus/idle.usdz", .walking: "Abyssus/walk.usdz"]
    let animationFilePaths: [HeroAnimationState: String]?
    
    func animationName(for state: HeroAnimationState) -> String {
        if let mapped = animationMap[state] {
            return mapped
        }
        return animationMap[.idle] ?? "idle"
    }
    
    func animationFilePath(for state: HeroAnimationState) -> String? {
        return animationFilePaths?[state]
    }
}

final class HeroRegistry {
    static let shared = HeroRegistry()
    
    private var heroes: [String: HeroDefinition] = [:]
    
    private init() {
        register(Self.albedo)
        register(Self.janeFosterThor)
        register(Self.abyssus)
    }
    
    func register(_ definition: HeroDefinition) {
        heroes[definition.identifier] = definition
    }
    
    func hero(with identifier: String) -> HeroDefinition? {
        heroes[identifier]
    }
    
    var allHeroes: [HeroDefinition] {
        heroes.values.sorted { $0.displayName < $1.displayName }
    }
    
    var defaultHero: HeroDefinition {
        guard let first = allHeroes.first else {
            return HeroRegistry.albedo
        }
        return first
    }
}

private extension HeroRegistry {
    static let albedo = HeroDefinition(
        identifier: "albedo",
        displayName: "Albedo",
        modelPath: "Resources/Models/Heroes/Albedo/idle.usdz",
        bundleSubdirectory: "Resources/Models/Heroes",
        scale: 10.0,
        rotation: SIMD4<Float>(0, 0, 0, 0), // Без поворота
        animationMap: [
            .idle: "dvl_mdl_albedo_idle_00",
            .walking: "dvl_mdl_albedo_idle_00",
            .attacking: "dvl_mdl_albedo_attack",
            .takingDamage: "dvl_mdl_albedo_damage",
            .dead: "dvl_mdl_albedo_dead",
            .usingSkill: "dvl_mdl_albedo_skill",
            .usingSpecialSkill: "dvl_mdl_albedo_spskill_00"
        ],
        animationFilePaths: [
            .idle: "Resources/Models/Heroes/Albedo/idle.usdz",
            .walking: "Resources/Models/Heroes/Albedo/walk.usdz"
        ]
    )
    
    static let janeFosterThor = HeroDefinition(
        identifier: "jane_foster_thor",
        displayName: "Jane Foster Thor",
        modelPath: "Resources/Models/Heroes/Jane_Foster_Thor.usdz",
        bundleSubdirectory: "Resources/Models/Heroes",
        scale: 0.05,
        rotation: SIMD4<Float>(0, 0, 0, 0), // Без поворота
        animationMap: [
            .idle: "wait",
            .walking: "walk",
            .attacking: "attack",
            .takingDamage: "damage",
            .dead: "dead",
            .usingSkill: "skill",
            .usingSpecialSkill: "ult"
        ],
        animationFilePaths: nil // Все анимации в одном файле
    )
    
    static let abyssus = HeroDefinition(
        identifier: "abyssus",
        displayName: "Abyssus, the Void Warlord",
        modelPath: "Resources/Models/Heroes/Abyssus/idle.usdz", // Базовая модель для геометрии
        bundleSubdirectory: "Resources/Models/Heroes",
        scale: 0.06,
        rotation: SIMD4<Float>(0, 0, 0, 0), // Без поворота
        animationMap: [
            .idle: "idle",
            .walking: "walk",
            .attacking: "attack",
            .takingDamage: "lose",
            .dead: "dead",
            .usingSkill: "skill_1",
            .usingSpecialSkill: "skill_2"
        ],
        animationFilePaths: [
            .idle: "Resources/Models/Heroes/Abyssus/idle.usdz",
            .walking: "Resources/Models/Heroes/Abyssus/walk.usdz",
            .attacking: "Resources/Models/Heroes/Abyssus/attack.usdz",
            .takingDamage: "Resources/Models/Heroes/Abyssus/lose.usdz",
            .dead: "Resources/Models/Heroes/Abyssus/dead.usdz",
            .usingSkill: "Resources/Models/Heroes/Abyssus/skill_1.usdz",
            .usingSpecialSkill: "Resources/Models/Heroes/Abyssus/skill_2.usdz"
        ]
    )
}
