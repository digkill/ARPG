//
//  SceneKitRenderer.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import Foundation
import SceneKit
import simd

struct Mob {
    var node: SCNNode
    var position: SIMD3<Float>
    var rotation: Float
    var velocity: SIMD3<Float>
    var maxHealth: Float
    var health: Float
    var maxMana: Float
    var mana: Float
    var attackDamage: Float
    var attackRange: Float
    var attackCooldown: Float
    var lastAttackTime: Float
    var aggroRange: Float
    var isAggressive: Bool
    var scale: Float
}

final class SceneKitRenderer: NSObject {
    let scene: SCNScene
    let cameraNode = SCNNode()
    var heroNode: SCNNode?
    var decorativeObjects: [DecorativeObject] = []
    var humans: [CharacterInstance] = []
    var mobs: [Mob] = []
    var heroScale: Float = 10.0
    var heroAnimationPlayers: [String: SCNAnimationPlayer] = [:]
    var currentHeroAnimation: HeroAnimationState = .idle
    var heroAttackAnimationTime: Float = 0
    var heroDamageAnimationTime: Float = 0
    var heroSkillAnimationTime: Float = 0
    var abilities: [AbilityKey: Ability] = [:]
    var heroStats = HeroStats()
    var selectedHero: HeroDefinition
    private var minimapCache = MinimapState(hero: nil, heroRotation: nil, objects: [], halfSize: WorldConstants.mapHalfSize)
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var fpsCounter: Int = 0
    private var fpsTimer: CFTimeInterval = 0
    private var reportedFPS: Int = 60
    private var cameraDistance: Float = 26
    private var cameraHeight: Float = 16
    private var cameraPitch: Float = 0.93
    private var cameraYaw: Float = .pi / 4
    private var cameraZoom: Float = 1.0
    private var desiredCameraZoom: Float = 1.0
    private let minZoom: Float = 0.7
    private let maxZoom: Float = 1.4
    private var cameraFollowHero = true
    private var cameraFocusPosition = SIMD3<Float>(0, 1.2, 0)
    private var cameraLookAheadDistance: Float = 6.0
    private var cameraFollowDamping: Float = 6.5
    private var cameraEdgePadding: Float = 4.0
    private var manualCameraOffset = SIMD3<Float>(repeating: 0)
    
    var inventory: [ItemSlot] = [
        ItemSlot(type: .tango, count: 3),
        ItemSlot(type: .clarity, count: 1),
        ItemSlot(type: .ironBranch, count: 1),
        ItemSlot(type: .faerieFire, count: 1),
        ItemSlot(type: .empty, count: 0),
        ItemSlot(type: .empty, count: 0)
    ]
    
    init(sceneView: SCNView, hero: HeroDefinition = HeroRegistry.shared.defaultHero) {
        scene = SCNScene()
        selectedHero = hero
        super.init()
        configure(sceneView: sceneView)
    }
    
    private func configure(sceneView: SCNView) {
        sceneView.scene = scene
        sceneView.backgroundColor = .black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.delegate = self
        sceneView.isPlaying = true
        
        setupCamera()
        setupLighting()
        setupGround()
        loadHero(hero: selectedHero)
        loadMobs()
        createDecorativeObjects()
        initializeAbilities()
        
        humans = [
            CharacterInstance(position: SIMD3<Float>(0, WorldConstants.groundY, 0),
                              rotation: 0,
                              velocity: SIMD3<Float>(repeating: 0),
                              scale: 1,
                              lastStepTime: 0)
        ]
        
        rebuildMinimapCache()
    }
    
    func updateGameState(deltaTime: Float) {
        guard !humans.isEmpty else { return }
        var hero = humans[0]
        let input = InputManager.shared.moveDirection
        // input.x: вправо положительный -> X положительный (вправо)
        // input.y: вверх положительный -> Z отрицательный (вперед, т.к. камера смотрит вниз по Z)
        let intended = SIMD3<Float>(input.x, 0, -input.y)
        let hasInput = simd_length(intended) > 0.05
        let moveSpeed: Float = heroStats.hasTree ? 6.5 : 5.0
        
        if hasInput {
            let direction = simd_normalize(intended)
            hero.velocity = direction * moveSpeed
            hero.rotation = atan2(direction.x, direction.z)
        } else {
            hero.velocity *= 0.85
        }
        
        hero.position += hero.velocity * deltaTime
        hero.position.x = min(max(hero.position.x, -WorldConstants.mapHalfSize), WorldConstants.mapHalfSize)
        hero.position.z = min(max(hero.position.z, -WorldConstants.mapHalfSize), WorldConstants.mapHalfSize)
        
        if simd_length(hero.velocity) > 0.1 {
            hero.lastStepTime += deltaTime
            if hero.lastStepTime > 0.45 {
                SoundManager.shared.playSound(name: "footstep", fileExtension: "mp3", volume: 0.25)
                hero.lastStepTime = 0
            }
        }
        
        humans[0] = hero
        
        if let heroNode = heroNode {
            heroNode.position = SCNVector3(hero.position.x, hero.position.y + heroScale, hero.position.z)
            heroNode.rotation = SCNVector4(0, 1, 0, hero.rotation)
        }
        
        updateHeroAnimations(deltaTime: deltaTime, hero: hero)
        
        if let heroLightNode = scene.rootNode.childNodes.first(where: { $0.light?.type == .omni }) {
            heroLightNode.position = SCNVector3(hero.position.x, hero.position.y + 3, hero.position.z)
        }
        
        if InputManager.shared.isAttackPressed {
            performHeroAttack()
        }
        // Обрабатываем способности в зависимости от героя
        if selectedHero.identifier == "abyssus" {
            if InputManager.shared.isSkill1Pressed {
                castAbility(.qRiftCleaver)
            }
            if InputManager.shared.isSkill2Pressed {
                castAbility(.wAbyssalChains)
            }
            if InputManager.shared.isSkill3Pressed {
                castAbility(.eVoidplateResonance)
            }
            if InputManager.shared.isSkill4Pressed {
                castAbility(.rRuptureOfTheVoid)
            }
        } else {
            if InputManager.shared.isSkill1Pressed {
                castAbility(.qAvalanche)
            }
            if InputManager.shared.isSkill2Pressed {
                castAbility(.wToss)
            }
            if InputManager.shared.isSkill3Pressed {
                castAbility(.eTreeGrab)
            }
            if InputManager.shared.isSkill4Pressed {
                castAbility(.rGrow)
            }
        }
        
        updateCamera(deltaTime: deltaTime, hero: hero)
        updateAbilities(deltaTime: deltaTime)
        updateInventory(deltaTime: deltaTime)
        updateMobs(deltaTime: deltaTime)
        rebuildMinimapCache()
    }
    
    private func updateCamera(deltaTime: Float, hero: CharacterInstance) {
        let baseHeroFocus = hero.position + SIMD3<Float>(0, 1.2, 0)
        var desiredFocus = baseHeroFocus
        
        if cameraFollowHero {
            let speed = simd_length(hero.velocity)
            if speed > 0.1 {
                let direction = simd_normalize(hero.velocity)
                let lookAhead = SIMD3<Float>(direction.x, 0, direction.z) * cameraLookAheadDistance
                desiredFocus += lookAhead
            }
        } else {
            desiredFocus = cameraFocusPosition
        }
        
        desiredFocus += manualCameraOffset
        
        desiredFocus.x = min(max(desiredFocus.x, -WorldConstants.mapHalfSize + cameraEdgePadding),
                             WorldConstants.mapHalfSize - cameraEdgePadding)
        desiredFocus.z = min(max(desiredFocus.z, -WorldConstants.mapHalfSize + cameraEdgePadding),
                             WorldConstants.mapHalfSize - cameraEdgePadding)
        
        let followWeight = 1 - pow(1 - min(max(cameraFollowDamping * 0.1, 0.01), 0.9), deltaTime)
        cameraFocusPosition = simd_mix(cameraFocusPosition,
                                       desiredFocus,
                                       SIMD3<Float>(repeating: followWeight))
        
        manualCameraOffset *= max(0, 1 - deltaTime * 1.5)
        
        cameraZoom += (desiredCameraZoom - cameraZoom) * 0.08
        cameraZoom = min(max(cameraZoom, minZoom), maxZoom)
        
        updateCameraMatrices()
    }
    
    private func updateCameraMatrices() {
        let zoomedDistance = cameraDistance * cameraZoom
        let horizontalDistance = cos(cameraPitch) * zoomedDistance
        let verticalOffset = sin(cameraPitch) * zoomedDistance + cameraHeight
        
        let offset = SIMD3<Float>(-sin(cameraYaw) * horizontalDistance,
                                  verticalOffset,
                                  -cos(cameraYaw) * horizontalDistance)
        let desiredPosition = cameraFocusPosition + offset
        
        cameraNode.position = SCNVector3(desiredPosition.x, desiredPosition.y, desiredPosition.z)
        cameraNode.look(at: SCNVector3(cameraFocusPosition.x, cameraFocusPosition.y, cameraFocusPosition.z))
    }
    
    func updateCameraPosition(target: SIMD3<Float>) {
        cameraFocusPosition = target
        updateCameraMatrices()
    }
    
    private func updateAbilities(deltaTime: Float) {
        for (key, var ability) in abilities {
            ability.currentCooldown = max(0, ability.currentCooldown - deltaTime)
            abilities[key] = ability
        }
    }
    
    private func updateInventory(deltaTime: Float) {
        for index in inventory.indices {
            var slot = inventory[index]
            if slot.cooldown > 0 {
                slot.cooldown = max(0, slot.cooldown - deltaTime)
            }
            inventory[index] = slot
        }
    }
    
    private func updateMobs(deltaTime: Float) {
        for index in mobs.indices {
            var mob = mobs[index]
            if mob.isAggressive {
                mob.velocity *= 0.9
                mob.position += mob.velocity * deltaTime
                mob.position.y = WorldConstants.groundY + 3
            }
            mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
            mob.node.rotation = SCNVector4(0, 1, 0, mob.rotation)
            mob.mana = min(mob.maxMana, mob.mana + 10 * deltaTime)
            mobs[index] = mob
        }
    }
    
    private func rebuildMinimapCache() {
        let hero2D = humans.first.map { SIMD2<Float>($0.position.x, $0.position.z) }
        let heroRot = humans.first?.rotation
        let objects2D = decorativeObjects.map { SIMD2<Float>($0.position.x, $0.position.z) }
        minimapCache = MinimapState(hero: hero2D, heroRotation: heroRot, objects: objects2D, halfSize: WorldConstants.mapHalfSize)
    }
    
    func getFPS() -> Int {
        reportedFPS
    }
    
    func getMinimapData() -> MinimapState {
        minimapCache
    }
    
    func adjustCameraZoom(by delta: Float) {
        desiredCameraZoom = min(max(desiredCameraZoom + delta, minZoom), maxZoom)
    }
    
    func centerCameraOnHero() {
        guard let hero = humans.first else { return }
        cameraFollowHero = true
        manualCameraOffset = SIMD3<Float>(repeating: 0)
        let target = hero.position + SIMD3<Float>(0, 1.2, 0)
        updateCameraPosition(target: target)
    }
    
    func panCamera(by delta: SIMD2<Float>) {
        manualCameraOffset.x += delta.x
        manualCameraOffset.z += delta.y
        cameraFollowHero = false
    }
}

extension SceneKitRenderer: SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let deltaTime = lastFrameTimestamp > 0 ? Float(time - lastFrameTimestamp) : 1.0 / 60.0
        lastFrameTimestamp = time
        fpsCounter += 1
        if time - fpsTimer >= 1.0 {
            reportedFPS = fpsCounter
            fpsCounter = 0
            fpsTimer = time
        }
        updateGameState(deltaTime: deltaTime)
    }
}
