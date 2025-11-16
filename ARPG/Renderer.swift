//
// Renderer.swift
// ARPG
//
// Created by Digkill on 15.11.2025.
//

import Foundation
import Metal
import MetalKit
import ModelIO
import QuartzCore
import simd

// Swift mirrors of enums/constants from ShaderTypes.h so they are visible here
enum BufferIndex: Int {
    case meshPositions = 0
    case meshGenerics = 1
    case uniforms = 2
}

enum TextureIndex: Int {
    case color = 0
    case ground = 1
}

let BufferIndexMeshPositions = BufferIndex.meshPositions
let BufferIndexMeshGenerics = BufferIndex.meshGenerics
let BufferIndexUniforms = BufferIndex.uniforms

let TextureIndexColor = TextureIndex.color
let TextureIndexGround = TextureIndex.ground

private let maxInFlightFrames = 3
private let groundY: Float = 0.0
private let mapHalfSize: Float = 45.0

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
    let description: String
}

enum AbilityKey: CaseIterable {
    case qAvalanche
    case wToss
    case eTreeGrab
    case rGrow
}

enum AbilityEffectType {
    case explosion
    case stunArea
    case tossProjectile
    case treeGrabBuff
    case growBuff
}

struct AbilityEffect {
    var position: SIMD3<Float>
    var radius: Float
    var duration: Float
    var damage: Float
    var stunDuration: Float
    var type: AbilityEffectType
    var timeRemaining: Float
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

// Item System for 6 slots
enum ItemType: Int {
    case empty = 0
    case tango = 1
    case clarity = 2
    case ironBranch = 3
    case faerieFire = 4
    case slipper = 5
    case mantle = 6
    case circlet = 7
    case stoutShield = 8
    case bracer = 9
    case nullTalisman = 10
    
    var name: String {
        switch self {
        case .tango: return "Tango"
        case .clarity: return "Clarity"
        case .ironBranch: return "Iron Branch"
        case .faerieFire: return "Faerie Fire"
        case .slipper: return "Slipper of Agility"
        case .mantle: return "Mantle of Intelligence"
        case .circlet: return "Circlet"
        case .stoutShield: return "Stout Shield"
        case .bracer: return "Bracer"
        case .nullTalisman: return "Null Talisman"
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
        case .slipper: return "Passive: +0 Agility"
        case .mantle: return "Passive: +0 Intelligence"
        case .circlet: return "Passive: +0 all stats"
        case .stoutShield: return "Passive: Blocks damage"
        case .bracer: return "Passive: +3 Strength"
        case .nullTalisman: return "Passive: +2 all stats"
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
        case .slipper:
            stats.agility += 0 // Placeholder, in real Dota it's +0 but components
        case .mantle:
            stats.intelligence += 0
        case .circlet:
            stats.strength += 0
            stats.agility += 0
            stats.intelligence += 0
        case .stoutShield:
            // Passive, no instant effect
            break
        case .bracer:
            stats.strength += 3
        case .nullTalisman:
            stats.strength += 2
            stats.agility += 2
            stats.intelligence += 2
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
        return type.cooldown
    }
    
    var isOnCooldown: Bool {
        return cooldown > 0
    }
    
    var isEmpty: Bool {
        return type == .empty || count == 0
    }
}

struct HeroTextures {
    var baseColor: MTLTexture?
    var normal: MTLTexture?
    var metallic: MTLTexture?
    var roughness: MTLTexture?
    var emission: MTLTexture?
    
    var hasTextures: Bool {
        return baseColor != nil
    }
}

final class Renderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader
    
    private var uniformBuffer: MTLBuffer
    private var currentBufferIndex: Int = 0
    
    private var colorTexture: MTLTexture?
    private var groundTexture: MTLTexture?
    private var defaultWhiteTexture: MTLTexture?
    private var heroTextures: HeroTextures?
    
    private var groundMesh: MTKMesh?
    private var heroMesh: MTKMesh?
   
    private var propMesh: MTKMesh?
    
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    private var viewMatrix: matrix_float4x4 = matrix_identity_float4x4
    private var cameraPosition = SIMD3<Float>(-24, 26, -24)
    private var cameraTarget = SIMD3<Float>(0, 4, 0)
    private var cameraDistance: Float = 16
    private var cameraHeight: Float = 16
    private var cameraPitch: Float = 0.93
    private var cameraYaw: Float = .pi / 4
    private var cameraZoom: Float = 1.0
    private var desiredCameraZoom: Float = 1.0
    private let minZoom: Float = 0.7
    private let maxZoom: Float = 1.4
    private var cameraPanInput = SIMD2<Float>(repeating: 0)
    private var cameraPanOffset = SIMD2<Float>(repeating: 0)
    
    private var humans: [CharacterInstance] = []
    var decorativeObjects: [DecorativeObject] = []
    private var heroScale: Float = 20.0
    private var heroLightPosition = SIMD3<Float>(0, 3, 0)
    private var heroLightRadius: Float = 18
    private var heroLightColor = SIMD3<Float>(1.0, 0.85, 0.65)
    private var heroLightIntensity: Float = 1.0
    
    private var minimapCache = MinimapState(hero: nil, heroRotation: nil, objects: [], halfSize: mapHalfSize)
    
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var fpsCounter: Int = 0
    private var fpsTimer: CFTimeInterval = 0
    private var reportedFPS: Int = 60
    
    private var abilities: [AbilityKey: Ability] = [:]
    private var abilityLevels: [AbilityKey: Int] = [
        .qAvalanche: 1,
        .wToss: 1,
        .eTreeGrab: 1,
        .rGrow: 1
    ]
    private var activeEffects: [AbilityEffect] = []
    private var heroStats = HeroStats()
    private let manaRegenPerSecond: Float = 0.75
    private var dayNightTime: Float = 0
    private let dayNightDuration: Float = 140
    // Солнце в центре карты на большой высоте
    private var currentLightColor = SIMD3<Float>(1.0, 0.95, 0.85) // Теплый солнечный цвет
    private var currentAmbientColor = SIMD3<Float>(0.35, 0.38, 0.42) // Яркое окружающее освещение
    private var currentLightDirection = SIMD3<Float>(0, -1, 0) // Направление для fallback
    private var sunPosition = SIMD3<Float>(0, 80, 0) // Солнце в центре карты (0,0,0) на высоте 80
    private var sunRadius: Float = 200.0 // Радиус действия солнца
    private var daylightFactor: Float = 1.0
    
    // Item Inventory - 6 slots
    var inventory: [ItemSlot] = [
        ItemSlot(type: .tango, count: 3),
        ItemSlot(type: .clarity, count: 1),
        ItemSlot(type: .ironBranch, count: 1),
        ItemSlot(type: .faerieFire, count: 1),
        ItemSlot(type: .empty, count: 0),
        ItemSlot(type: .empty, count: 0)
    ]
    
    init?(metalKitView view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            print("ERROR: Unable to create Metal device")
            return nil
        }
        
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)
        
        view.device = device
        view.depthStencilPixelFormat = .depth32Float
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = 1
        
        guard let library = device.makeDefaultLibrary() else { return nil }
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineDescriptor.vertexDescriptor = Renderer.buildMetalVertexDescriptor()
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("ERROR: Pipeline creation failed \(error)")
            return nil
        }
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.isDepthWriteEnabled = true
        depthDescriptor.depthCompareFunction = .lessEqual
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            return nil
        }
        self.depthState = depthState
        
        let uniformSize = MemoryLayout<Uniforms>.stride * maxInFlightFrames
        guard let buffer = device.makeBuffer(length: uniformSize, options: .storageModeShared) else {
            return nil
        }
        uniformBuffer = buffer
        
        defaultWhiteTexture = Renderer.makeFallbackTexture(device: device)
        colorTexture = Renderer.loadTexture(named: "ColorMap", loader: textureLoader) ?? defaultWhiteTexture
        
        // Загружаем terrain.jpg для земли
        let terrainOptions: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.bottomLeft
        ]
        
        // Пробуем загрузить из разных мест
        var terrainURL: URL?
        terrainURL = Bundle.main.url(forResource: "terrain", withExtension: "jpg", subdirectory: "Resources/Images")
        if terrainURL == nil {
            terrainURL = Bundle.main.url(forResource: "terrain", withExtension: "jpg")
        }
        if terrainURL == nil {
            // Прямой путь к файлу
            let directPath = "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Images/terrain.jpg"
            terrainURL = URL(fileURLWithPath: directPath)
        }
        
        if let url = terrainURL, FileManager.default.fileExists(atPath: url.path) {
            groundTexture = try? textureLoader.newTexture(URL: url, options: terrainOptions)
            if groundTexture != nil {
                print("✅ Загружена текстура terrain.jpg")
            }
        }
        
        // Fallback на FantasyTerrain, если terrain.jpg не загрузился
        if groundTexture == nil {
            groundTexture = Renderer.loadTexture(named: "FantasyTerrain", loader: textureLoader) ?? defaultWhiteTexture
            print("⚠️ Используется fallback текстура FantasyTerrain")
        }
        
        groundMesh = Renderer.makePlaneMesh(device: device, size: 100)
        if let heroModelMesh = Renderer.loadHeroMesh(device: device) {
            heroMesh = heroModelMesh
            print("✅ Loaded JungleSoulbreaker hero mesh")
            // Загружаем текстуры для героя
            heroTextures = Renderer.loadHeroTextures(loader: textureLoader)
            if heroTextures?.hasTextures == true {
                print("✅ Loaded hero textures (BaseColor: \(heroTextures?.baseColor != nil), Normal: \(heroTextures?.normal != nil), Metallic: \(heroTextures?.metallic != nil), Roughness: \(heroTextures?.roughness != nil))")
            } else {
                print("⚠️ Hero textures not loaded")
            }
        }
  
        propMesh = Renderer.makeBoxMesh(device: device, size: SIMD3<Float>(1, 1.5, 1))
        
        humans = [CharacterInstance(position: SIMD3<Float>(0, groundY, 0),
                                    rotation: 0,
                                    velocity: SIMD3<Float>(repeating: 0),
                                    scale: 1,
                                    lastStepTime: 0)]
        decorativeObjects = Renderer.spawnProps(count: 80)
        
        super.init()
        
        rebuildMinimapCache()
        initializeAbilities()
        updateCameraMatrices()
        projectionMatrix = Renderer.makeProjectionMatrix(for: view.drawableSize)
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        projectionMatrix = Renderer.makeProjectionMatrix(for: size)
    }
    
    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        
        let timestamp = CACurrentMediaTime()
        let deltaTime = lastFrameTimestamp > 0 ? Float(timestamp - lastFrameTimestamp) : 1.0 / 60.0
        lastFrameTimestamp = timestamp
        fpsCounter += 1
        if timestamp - fpsTimer >= 1.0 {
            reportedFPS = fpsCounter
            fpsCounter = 0
            fpsTimer = timestamp
        }
        
        updateGameState(deltaTime: deltaTime)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        
        // Draw ground
        if let groundMesh = groundMesh {
            let groundScale = matrix4x4_scale(1, 1, 1)
            let groundTransform = simd_mul(matrix4x4_translation(0, groundY, 0), groundScale)
            // Белый цвет для чистой текстуры без покраски
            let groundColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
            draw(mesh: groundMesh,
                 transform: groundTransform,
                 baseColor: groundColor,
                 material: .ground,
                 colorTexture: colorTexture,
                 secondTexture: groundTexture,
                 encoder: encoder)
        }
        
        // Draw decorative props
        for prop in decorativeObjects {
            guard let propMesh = propMesh else { continue }
            let scaleMatrix = matrix4x4_scale(prop.scale, prop.scale, prop.scale)
            let transform = simd_mul(matrix4x4_translation(prop.position.x, prop.position.y, prop.position.z), scaleMatrix)
            let propColor = SIMD4<Float>(0.35 + 0.25 * daylightFactor,
                                         0.3 + 0.25 * daylightFactor,
                                         0.26 + 0.16 * daylightFactor,
                                         1.0)
            draw(mesh: propMesh,
                 transform: transform,
                 baseColor: propColor,
                 material: .character,
                 colorTexture: colorTexture,
                 secondTexture: groundTexture,
                 encoder: encoder)
        }
        
      
        
        // Draw hero
        if let heroMesh = heroMesh, let hero = humans.first {
            let rotationMatrix = matrix4x4_rotation(radians: hero.rotation, axis: SIMD3<Float>(0, 1, 0))
            let scaleMatrix = matrix4x4_scale(heroScale, heroScale, heroScale)
            let modelMatrix = simd_mul(matrix4x4_translation(hero.position.x, hero.position.y + 1.0 * heroScale, hero.position.z),
                                       simd_mul(rotationMatrix, scaleMatrix))
            // Используем белый цвет, чтобы текстура модели отображалась без искажений
            let heroColor = SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
            draw(mesh: heroMesh,
                 transform: modelMatrix,
                 baseColor: heroColor,
                 material: .character,
                 colorTexture: heroTextures?.baseColor ?? colorTexture,
                 secondTexture: nil,
                 encoder: encoder)
        }
        
        drawAbilityEffects(encoder: encoder)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // MARK: - Game State
    
    private func updateGameState(deltaTime: Float) {
        guard !humans.isEmpty else { return }
        var hero = humans[0]
        let input = InputManager.shared.moveDirection
        
        // Инвертируем управление для правильной работы
        let intended = SIMD3<Float>(-input.x, 0, -input.y)
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
        hero.position.x = min(max(hero.position.x, -mapHalfSize), mapHalfSize)
        hero.position.z = min(max(hero.position.z, -mapHalfSize), mapHalfSize)
        
        if simd_length(hero.velocity) > 0.1 {
            hero.lastStepTime += deltaTime
            if hero.lastStepTime > 0.45 {
                SoundManager.shared.playSound(name: "footstep", fileExtension: "mp3", volume: 0.25)
                hero.lastStepTime = 0
            }
        }
        
        humans[0] = hero
        heroLightPosition = hero.position + SIMD3<Float>(0, 2.5, 0)
        updateCameraMatrices()
        updateAbilities(deltaTime: deltaTime)
        updateInventory(deltaTime: deltaTime)
        updateDayNightCycle(deltaTime: deltaTime)
        rebuildMinimapCache()
    }
    
    private func updateInventory(deltaTime: Float) {
        for i in 0..<inventory.count {
            var slot = inventory[i]
            if slot.cooldown > 0 {
                slot.cooldown = max(0, slot.cooldown - deltaTime)
            }
            inventory[i] = slot
        }
    }
    
    private func updateCameraMatrices() {
        guard let hero = humans.first else { return }
        
        // Smooth pan offset for classic Dota-style edge panning
        let maxPanDistance: Float = cameraDistance * 0.55
        let desiredPanOffset = SIMD2<Float>(cameraPanInput.x * maxPanDistance,
                                            cameraPanInput.y * maxPanDistance)
        cameraPanOffset = simd_mix(cameraPanOffset,
                                   desiredPanOffset,
                                   SIMD2<Float>(repeating: 0.12))
        
        // Zoom smoothing
        cameraZoom += (desiredCameraZoom - cameraZoom) * 0.08
        cameraZoom = min(max(cameraZoom, minZoom), maxZoom)
        
        // Target the hero with slight offset (camera hovers above left shoulder)
        var desiredTarget = hero.position + SIMD3<Float>(0, 1.2, 0)
        desiredTarget.x += cameraPanOffset.x
        desiredTarget.z += cameraPanOffset.y
        desiredTarget.x = min(max(desiredTarget.x, -mapHalfSize + 6), mapHalfSize - 6)
        desiredTarget.z = min(max(desiredTarget.z, -mapHalfSize + 6), mapHalfSize - 6)
        
        let zoomedDistance = cameraDistance * cameraZoom
        let horizontalDistance = cos(cameraPitch) * zoomedDistance
        let verticalOffset = sin(cameraPitch) * zoomedDistance + cameraHeight
        
        let offset = SIMD3<Float>(-sin(cameraYaw) * horizontalDistance,
                                  verticalOffset,
                                  -cos(cameraYaw) * horizontalDistance)
        let desiredPosition = desiredTarget + offset
        
        cameraTarget = simd_mix(cameraTarget,
                                desiredTarget,
                                SIMD3<Float>(repeating: 0.18))
        cameraPosition = simd_mix(cameraPosition,
                                  desiredPosition,
                                  SIMD3<Float>(repeating: 0.14))
        viewMatrix = matrix_look_at_right_hand(eye: cameraPosition,
                                               target: cameraTarget,
                                               up: SIMD3<Float>(0, 1, 0))
    }
    
    private func rebuildMinimapCache() {
        let hero2D = humans.first.map { SIMD2<Float>($0.position.x, $0.position.z) }
        let heroRot = humans.first?.rotation
        var objects: [SIMD2<Float>] = []
        for obj in decorativeObjects.prefix(120) {
            objects.append(SIMD2<Float>(obj.position.x, obj.position.z))
        }
        minimapCache = MinimapState(hero: hero2D, heroRotation: heroRot, objects: objects, halfSize: mapHalfSize)
    }
    
    private func updateDayNightCycle(deltaTime: Float) {
        // Статическое солнце сверху - не обновляем направление
        // Солнце всегда сверху для постоянного освещения
        currentLightDirection = SIMD3<Float>(0, -1, 0) // Солнце прямо сверху
        currentLightColor = SIMD3<Float>(1.0, 0.95, 0.85) // Теплый солнечный цвет
        currentAmbientColor = SIMD3<Float>(0.35, 0.38, 0.42) // Яркое окружающее освещение
        daylightFactor = 1.0
        
        // Обновляем только свет героя (если нужно)
        heroLightIntensity = 0.8
        heroLightColor = SIMD3<Float>(1.0, 0.85, 0.65)
    }
    
    // MARK: - Abilities
    
    private func initializeAbilities() {
        abilities[.qAvalanche] = Ability(name: "Avalanche",
                                         manaCost: 80,
                                         cooldown: 12,
                                         currentCooldown: 0,
                                         castRange: 8,
                                         description: "AoE damage around target point")
        abilities[.wToss] = Ability(name: "Toss",
                                    manaCost: 70,
                                    cooldown: 9,
                                    currentCooldown: 0,
                                    castRange: 6,
                                    description: "Throws nearest object at position")
        abilities[.eTreeGrab] = Ability(name: "Tree Grab",
                                        manaCost: 60,
                                        cooldown: 18,
                                        currentCooldown: 0,
                                        castRange: 0,
                                        description: "Grab a tree for bonus damage")
        abilities[.rGrow] = Ability(name: "Grow",
                                    manaCost: 100,
                                    cooldown: 45,
                                    currentCooldown: 0,
                                    castRange: 0,
                                    description: "Permanent strength buff")
    }
    
    private func updateAbilities(deltaTime: Float) {
        for key in AbilityKey.allCases {
            if var ability = abilities[key], ability.currentCooldown > 0 {
                ability.currentCooldown = max(0, ability.currentCooldown - deltaTime)
                abilities[key] = ability
            }
        }
        
        heroStats.mana = min(heroStats.maxMana, heroStats.mana + manaRegenPerSecond * deltaTime)
        for index in activeEffects.indices {
            activeEffects[index].timeRemaining -= deltaTime
        }
        activeEffects.removeAll { $0.timeRemaining <= 0 }
        
        heroStats.health = min(heroStats.maxHealth, heroStats.health + 0.5 * deltaTime)
    }
    
    @MainActor
    func castAbility(_ key: AbilityKey, targetPos: SIMD3<Float>? = nil) {
        guard let hero = humans.first,
              var ability = abilities[key],
              ability.currentCooldown <= 0,
              heroStats.mana >= ability.manaCost else { return }
        
        heroStats.mana -= ability.manaCost
        ability.currentCooldown = ability.cooldown
        abilities[key] = ability
        
        switch key {
        case .qAvalanche:
            castAvalanche(targetPos: targetPos ?? hero.position)
        case .wToss:
            castToss(targetPos: targetPos ?? hero.position)
        case .eTreeGrab:
            castTreeGrab()
        case .rGrow:
            castGrow()
        }
        
        SoundManager.shared.playSound(name: ability.name.lowercased(), fileExtension: "mp3", volume: 0.7)
    }
    
    @MainActor
    func levelUpAbility(_ key: AbilityKey) {
        guard let level = abilityLevels[key], level < 4 else { return }
        abilityLevels[key] = level + 1
        print("📈 \(abilities[key]?.name ?? "") -> level \(level + 1)")
    }
    
    // MARK: - Items
    
    @MainActor
    func useItem(at slotIndex: Int) {
        guard slotIndex < inventory.count else { return }
        var slot = inventory[slotIndex]
        guard !slot.isEmpty, !slot.isOnCooldown else { return }
        
        // Apply effect
        slot.type.applyEffect(to: &heroStats)
        
        // Consume if consumable
        if slot.type == .tango || slot.type == .clarity || slot.type == .faerieFire {
            slot.count -= 1
            if slot.count <= 0 {
                slot.type = .empty
                slot.count = 0
            }
        }
        
        // Set cooldown
        slot.cooldown = slot.type.cooldown
        
        inventory[slotIndex] = slot
        
        print("📦 Used \(slot.type.name) from slot \(slotIndex)")
        
        // Play sound if available
        SoundManager.shared.playSound(name: slot.type.name.lowercased().replacingOccurrences(of: " ", with: ""), fileExtension: "mp3", volume: 0.6)
    }
    
    @MainActor
    func equipItem(_ type: ItemType, to slotIndex: Int) {
        guard slotIndex < inventory.count else { return }
        
        // Simple equip: move to slot if empty or replace
        var slot = inventory[slotIndex]
        slot.type = type
        slot.count = 1
        slot.cooldown = 0
        inventory[slotIndex] = slot
        
        print("🎒 Equipped \(type.name) to slot \(slotIndex)")
    }
    
    private func castAvalanche(targetPos: SIMD3<Float>) {
        guard let hero = humans.first else { return }
        let level = Float(abilityLevels[.qAvalanche] ?? 1)
        let radius: Float = 4.5 + level
        let damage = 110 + (level - 1) * 40 + heroStats.strength * 0.25
        
        let effect = AbilityEffect(position: targetPos,
                                   radius: radius,
                                   duration: 0.6,
                                   damage: damage,
                                   stunDuration: 1.0,
                                   type: .explosion,
                                   timeRemaining: 0.6)
        activeEffects.append(effect)
        
        for index in decorativeObjects.indices {
            let dist = simd_distance(decorativeObjects[index].position, targetPos)
            if dist < radius {
                decorativeObjects[index].scale = max(0.4, decorativeObjects[index].scale * 0.95)
            }
        }
        
        print("💥 Avalanche by \(hero.position) radius \(radius)")
    }
    
    private func castToss(targetPos: SIMD3<Float>) {
        guard let hero = humans.first else { return }
        if let index = nearestObjectInRadius(center: hero.position, radius: 6) {
            var obj = decorativeObjects[index]
            obj.position = targetPos
            decorativeObjects[index] = obj
            
            let effect = AbilityEffect(position: targetPos,
                                       radius: 2.5,
                                       duration: 0.8,
                                       damage: 80,
                                       stunDuration: 0.5,
                                       type: .tossProjectile,
                                       timeRemaining: 0.8)
            activeEffects.append(effect)
            print("🪨 Toss impact near \(targetPos)")
        }
    }
    
    private func castTreeGrab() {
        heroStats.hasTree.toggle()
        heroStats.treeBonusDamage = heroStats.hasTree ? 55 : 0
        heroStats.attackRange = heroStats.hasTree ? 3.2 : 2.5
        
        activeEffects.append(AbilityEffect(position: humans.first?.position ?? .zero,
                                           radius: heroStats.attackRange,
                                           duration: 10,
                                           damage: 0,
                                           stunDuration: 0,
                                           type: .treeGrabBuff,
                                           timeRemaining: heroStats.hasTree ? 12 : 0.3))
        print("🌳 Tree Grab \(heroStats.hasTree ? "enabled" : "disabled")")
    }
    
    private func castGrow() {
        let level = Float(abilityLevels[.rGrow] ?? 1)
        heroScale *= 1.05 + level * 0.05
        heroStats.strength += 12 * level
        heroStats.baseDamage += 25 * level
        heroStats.growMultiplier += 0.15
        
        activeEffects.append(AbilityEffect(position: humans.first?.position ?? .zero,
                                           radius: heroScale * 1.2,
                                           duration: 5,
                                           damage: 0,
                                           stunDuration: 0,
                                           type: .growBuff,
                                           timeRemaining: 5))
        print("💪 Grow! scale \(heroScale)")
    }
    
    private func nearestObjectInRadius(center: SIMD3<Float>, radius: Float) -> Int? {
        var nearestIndex: Int?
        var nearestDist = radius
        for (index, object) in decorativeObjects.enumerated() {
            let distance = simd_distance(object.position, center)
            if distance < nearestDist {
                nearestDist = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }
    
    private func drawAbilityEffects(encoder: MTLRenderCommandEncoder) {
  
        for effect in activeEffects {
            let radiusScale = max(effect.radius, 0.5)
            let scaleMatrix = matrix4x4_scale(radiusScale, 1, radiusScale)
            let translate = matrix4x4_translation(effect.position.x, groundY + 0.03, effect.position.z)
            let _ = simd_mul(translate, scaleMatrix) // model matrix (not used in current implementation)
            
            let alpha = max(0.05, effect.timeRemaining / max(effect.duration, 0.01))
            let color: SIMD4<Float>
            switch effect.type {
            case .explosion:
                color = SIMD4<Float>(1.0, 0.3, 0.2, alpha)
            case .tossProjectile:
                color = SIMD4<Float>(0.9, 0.8, 0.3, alpha)
            case .treeGrabBuff:
                color = SIMD4<Float>(0.3, 0.8, 0.4, alpha)
            case .growBuff:
                color = SIMD4<Float>(0.5, 0.7, 1.0, alpha)
            case .stunArea:
                color = SIMD4<Float>(0.7, 0.4, 1.0, alpha)
            @unknown default:
                color = SIMD4<Float>(0.8, 0.4, 0.2, alpha)
            }
            
            // Color is defined but not used in current implementation
            // (effect rendering code was removed during SceneKit migration)
            _ = color
        }
    }
    
    // MARK: - Public API
    
    func getHeroUIState() -> (health: Float,
                              mana: Float,
                              level: Int,
                              abilities: [AbilityKey: (cd: Float, maxCD: Float, level: Int)],
                              inventory: [ItemSlot]) {
        var values: [AbilityKey: (Float, Float, Int)] = [:]
        for key in AbilityKey.allCases {
            let cooldown = abilities[key]?.currentCooldown ?? 0
            let maxCooldown = abilities[key]?.cooldown ?? 1
            let level = abilityLevels[key] ?? 1
            values[key] = (cooldown, maxCooldown, level)
        }
        return (heroStats.health / heroStats.maxHealth,
                heroStats.mana / heroStats.maxMana,
                heroStats.level,
                values,
                inventory)
    }
    
    func getFPS() -> Int {
        return reportedFPS
    }

    func getMinimapData() -> MinimapState {
        return minimapCache
    }
    
    func setCameraPanInput(_ input: SIMD2<Float>) {
        let clampedX = min(max(input.x, -1), 1)
        let clampedY = min(max(input.y, -1), 1)
        cameraPanInput = SIMD2<Float>(clampedX, clampedY)
    }
    
    func adjustCameraZoom(by delta: Float) {
        desiredCameraZoom = min(max(desiredCameraZoom + delta, minZoom), maxZoom)
    }
    
    func centerCameraOnHero() {
        cameraPanInput = SIMD2<Float>(repeating: 0)
    }
    
    // MARK: - Rendering helpers
    
    private func draw(mesh: MTKMesh,
                      transform: matrix_float4x4,
                      baseColor: SIMD4<Float>,
                      material: MaterialType,
                      colorTexture: MTLTexture?,
                      secondTexture: MTLTexture?,
                      encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms()
        uniforms.projectionMatrix = projectionMatrix
        uniforms.modelViewMatrix = simd_mul(viewMatrix, transform)
        let normalMatrix3x3 = matrix_float3x3(columns: (
            SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3<Float>(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        ))
        uniforms.normalMatrix = normalMatrix3x3
        uniforms.time = Float(CACurrentMediaTime())
        uniforms.lightDirection = currentLightDirection
        uniforms.lightColor = currentLightColor
        uniforms.ambientColor = currentAmbientColor
        uniforms.sunPosition = sunPosition
        uniforms.sunRadius = sunRadius
        uniforms.baseColor = baseColor
        uniforms.materialType = material
        uniforms.terrainUV = SIMD4<Float>(10, 10, 0, 0)
        uniforms.terrainColorDetail = SIMD4<Float>(0.95, 1.02, 0.95, 0.2)
        uniforms.terrainWorld = SIMD4<Float>(0, 0, 0, material == .ground ? 0 : 1)
        uniforms.heroLightPositionRadius = SIMD4<Float>(heroLightPosition.x, heroLightPosition.y, heroLightPosition.z, heroLightRadius)
        uniforms.heroLightColorIntensity = SIMD4<Float>(heroLightColor.x, heroLightColor.y, heroLightColor.z, heroLightIntensity)
        
        encoder.setVertexBuffer(mesh.vertexBuffers[Int(BufferIndexMeshPositions.rawValue)].buffer,
                                offset: mesh.vertexBuffers[Int(BufferIndexMeshPositions.rawValue)].offset,
                                index: Int(BufferIndexMeshPositions.rawValue))
        encoder.setVertexBuffer(mesh.vertexBuffers[Int(BufferIndexMeshGenerics.rawValue)].buffer,
                                offset: mesh.vertexBuffers[Int(BufferIndexMeshGenerics.rawValue)].offset,
                                index: Int(BufferIndexMeshGenerics.rawValue))
        encoder.setVertexBytes(&uniforms,
                               length: MemoryLayout<Uniforms>.stride,
                               index: Int(BufferIndexUniforms.rawValue))
        
        encoder.setFragmentBytes(&uniforms,
                                 length: MemoryLayout<Uniforms>.stride,
                                 index: Int(BufferIndexUniforms.rawValue))
        encoder.setFragmentTexture(colorTexture ?? defaultWhiteTexture, index: Int(TextureIndexColor.rawValue))
        encoder.setFragmentTexture(secondTexture ?? defaultWhiteTexture, index: Int(TextureIndexGround.rawValue))
        
        for submesh in mesh.submeshes {
            encoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                          indexCount: submesh.indexCount,
                                          indexType: submesh.indexType,
                                          indexBuffer: submesh.indexBuffer.buffer,
                                          indexBufferOffset: submesh.indexBuffer.offset)
        }
    }
    
    // MARK: - Builders
    
    private static func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = Int(BufferIndexMeshPositions.rawValue)
        
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = 0
        descriptor.attributes[1].bufferIndex = Int(BufferIndexMeshGenerics.rawValue)
        
        descriptor.attributes[2].format = .float3
        descriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride
        descriptor.attributes[2].bufferIndex = Int(BufferIndexMeshGenerics.rawValue)
        
        descriptor.layouts[Int(BufferIndexMeshPositions.rawValue)].stride = MemoryLayout<SIMD3<Float>>.stride
        descriptor.layouts[Int(BufferIndexMeshGenerics.rawValue)].stride = MemoryLayout<SIMD2<Float>>.stride + MemoryLayout<SIMD3<Float>>.stride
        return descriptor
    }
    
    private static func makeModelVertexDescriptor() -> MDLVertexDescriptor {
        let mdl = MTKModelIOVertexDescriptorFromMetal(buildMetalVertexDescriptor())
        (mdl.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        (mdl.attributes[1] as? MDLVertexAttribute)?.name = MDLVertexAttributeTextureCoordinate
        (mdl.attributes[2] as? MDLVertexAttribute)?.name = MDLVertexAttributeNormal
        return mdl
    }
    
    private static func loadHeroMesh(device: MTLDevice) -> MTKMesh? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let descriptor = makeModelVertexDescriptor()
        
        let absoluteURL = URL(fileURLWithPath: "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Models/JungleSoulbreaker/JungleSoulbreaker.obj")
        
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "JungleSoulbreaker", withExtension: "obj", subdirectory: "Resources/Models/JungleSoulbreaker"),
            Bundle.main.url(forResource: "JungleSoulbreaker", withExtension: "obj", subdirectory: "Resources/Models"),
            Bundle.main.url(forResource: "JungleSoulbreaker", withExtension: "obj"),
            absoluteURL
        ]
        
        for case let url? in possibleURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                let asset = MDLAsset(url: url, vertexDescriptor: descriptor, bufferAllocator: allocator)
                asset.loadTextures()
                if let (mdlMeshes, mtkMeshes) = try? MTKMesh.newMeshes(asset: asset, device: device),
                   let mesh = mtkMeshes.first,
                   let mdlMesh = mdlMeshes.first {
                    mdlMesh.vertexDescriptor = descriptor
                    print("✅ Successfully loaded mesh from: \(url.path)")
                    return mesh
                }
            }
        }
        return nil
    }
    
    private static func makePlaneMesh(device: MTLDevice, size: Float) -> MTKMesh? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let extent = SIMD3<Float>(size, 0, size)
        let plane = MDLMesh(planeWithExtent: extent,
                            segments: SIMD2<UInt32>(10, 10),
                            geometryType: .triangles,
                            allocator: allocator)
        plane.vertexDescriptor = makeModelVertexDescriptor()
        return try? MTKMesh(mesh: plane, device: device)
    }
    
    private static func makeBoxMesh(device: MTLDevice, size: SIMD3<Float>) -> MTKMesh? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let mesh = MDLMesh(boxWithExtent: size,
                           segments: SIMD3<UInt32>(1, 1, 1),
                           inwardNormals: false,
                           geometryType: .triangles,
                           allocator: allocator)
        mesh.vertexDescriptor = makeModelVertexDescriptor()
        return try? MTKMesh(mesh: mesh, device: device)
    }
    
    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = 1
        descriptor.height = 1
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let color: [UInt8] = [255, 255, 255, 255]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: color, bytesPerRow: 4)
        return texture
    }
    
    private static func loadTexture(named name: String, loader: MTKTextureLoader) -> MTLTexture? {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.bottomLeft
        ]
        if let texture = try? loader.newTexture(name: name, scaleFactor: 1.0, bundle: .main, options: options) {
            return texture
        }
        // Пробуем загрузить .png
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return try? loader.newTexture(URL: url, options: options)
        }
        // Пробуем загрузить .jpg
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return try? loader.newTexture(URL: url, options: options)
        }
        return nil
    }
    
    private static func loadHeroTextures(loader: MTKTextureLoader) -> HeroTextures {
        let texturesPath = "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Models/JungleSoulbreaker/textures"
        
        var heroTextures = HeroTextures(baseColor: nil, normal: nil, metallic: nil, roughness: nil, emission: nil)
        
        // Функция для загрузки текстуры по имени
        func loadTexture(name: String, sRGB: Bool = true) -> MTLTexture? {
            let options: [MTKTextureLoader.Option: Any] = [
                .SRGB: sRGB,
                .origin: MTKTextureLoader.Origin.bottomLeft
            ]
            
            // Пробуем загрузить из Bundle
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Resources/Models/JungleSoulbreaker/textures") {
                if let texture = try? loader.newTexture(URL: url, options: options) {
                    return texture
                }
            }
            
            // Пробуем прямой путь к файлу
            let directPath = "\(texturesPath)/\(name).png"
            if FileManager.default.fileExists(atPath: directPath) {
                let directURL = URL(fileURLWithPath: directPath)
                if let texture = try? loader.newTexture(URL: directURL, options: options) {
                    return texture
                }
            }
            
            return nil
        }
        
        // Загружаем текстуры в порядке приоритета (1-11)
        for i in 1...11 {
            let prefix = "\(i)_"
            
            // BaseColor (sRGB)
            if heroTextures.baseColor == nil {
                if let texture = loadTexture(name: "\(prefix)BaseColor", sRGB: true) {
                    heroTextures.baseColor = texture
                    print("✅ Loaded hero BaseColor: \(prefix)BaseColor.png")
                }
            }
            
            // Normal map (не sRGB)
            if heroTextures.normal == nil {
                if let texture = loadTexture(name: "\(prefix)Normal", sRGB: false) {
                    heroTextures.normal = texture
                    print("✅ Loaded hero Normal: \(prefix)Normal.png")
                }
            }
            
            // Metallic (не sRGB)
            if heroTextures.metallic == nil {
                if let texture = loadTexture(name: "\(prefix)Metallic", sRGB: false) {
                    heroTextures.metallic = texture
                    print("✅ Loaded hero Metallic: \(prefix)Metallic.png")
                }
            }
            
            // Roughness (не sRGB)
            if heroTextures.roughness == nil {
                if let texture = loadTexture(name: "\(prefix)Roughness", sRGB: false) {
                    heroTextures.roughness = texture
                    print("✅ Loaded hero Roughness: \(prefix)Roughness.png")
                }
            }
            
            // Emission (sRGB)
            if heroTextures.emission == nil {
                if let texture = loadTexture(name: "\(prefix)Emission", sRGB: true) {
                    heroTextures.emission = texture
                    print("✅ Loaded hero Emission: \(prefix)Emission.png")
                }
            }
            
            // Если загрузили все основные текстуры, можно выйти
            if heroTextures.baseColor != nil && heroTextures.normal != nil {
                break
            }
        }
        
        return heroTextures
    }
    
    private static func spawnProps(count: Int) -> [DecorativeObject] {
        var objects: [DecorativeObject] = []
        for _ in 0..<count {
            let x = Float.random(in: -mapHalfSize...mapHalfSize)
            let z = Float.random(in: -mapHalfSize...mapHalfSize)
            let scale = Float.random(in: 0.6...1.5)
            objects.append(DecorativeObject(position: SIMD3<Float>(x, groundY, z), scale: scale))
        }
        return objects
    }
    
    private static func makeProjectionMatrix(for size: CGSize) -> matrix_float4x4 {
        let aspect = Float(size.width / max(size.height, 1))
        return matrix_perspective_right_hand(fovyRadians: Float.pi / 3,
                                             aspectRatio: aspect,
                                             nearZ: 0.1,
                                             farZ: 200)
    }
}

// MARK: - Matrix helpers

private func matrix_perspective_right_hand(fovyRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let yScale = 1 / tan(fovyRadians * 0.5)
    let xScale = yScale / aspectRatio
    let zRange = farZ - nearZ
    let zScale = -(farZ + nearZ) / zRange
    let wzScale = -2 * farZ * nearZ / zRange
    
    return matrix_float4x4(columns: (
        SIMD4<Float>(xScale, 0, 0, 0),
        SIMD4<Float>(0, yScale, 0, 0),
        SIMD4<Float>(0, 0, zScale, -1),
        SIMD4<Float>(0, 0, wzScale, 0)
    ))
}

private func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let zAxis = simd_normalize(eye - target)
    let xAxis = simd_normalize(simd_cross(up, zAxis))
    let yAxis = simd_cross(zAxis, xAxis)
    
    return matrix_float4x4(columns: (
        SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
        SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
        SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
        SIMD4<Float>(-simd_dot(xAxis, eye),
                     -simd_dot(yAxis, eye),
                     -simd_dot(zAxis, eye),
                     1)
    ))
}

private func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

private func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
    return matrix_float4x4(columns: (
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let a = simd_normalize(axis)
    let cos = cosf(radians)
    let sin = sinf(radians)
    let c = 1 - cos
    
    return matrix_float4x4(columns: (
        SIMD4<Float>(cos + a.x * a.x * c,
                     a.x * a.y * c - a.z * sin,
                     a.x * a.z * c + a.y * sin,
                     0),
        SIMD4<Float>(a.y * a.x * c + a.z * sin,
                     cos + a.y * a.y * c,
                     a.y * a.z * c - a.x * sin,
                     0),
        SIMD4<Float>(a.z * a.x * c - a.y * sin,
                     a.z * a.y * c + a.x * sin,
                     cos + a.z * a.z * c,
                     0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}
