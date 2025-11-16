//
//  SceneKitRenderer.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import Foundation
import SceneKit
import simd

// Игровые структуры определены в Renderer.swift - используем их оттуда

private let groundY: Float = 0.0
private let mapHalfSize: Float = 45.0
private let heroPlatformRadius: Float = 1.4

// Структура для мобов
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

// Система анимаций героя
enum HeroAnimationState {
    case idle
    case walking
    case attacking
    case takingDamage
    case dead
    case usingSkill
    case usingSpecialSkill
}

final class SceneKitRenderer: NSObject {
    var scene: SCNScene!
    var cameraNode: SCNNode!
    var heroNode: SCNNode?
    var groundNode: SCNNode!
    var heroPlatformNode: SCNNode?
    
    private var humans: [CharacterInstance] = []
    var decorativeObjects: [DecorativeObject] = []
    private var mobs: [Mob] = []
    private var heroScale: Float = 10.0
    
    // Система анимаций
    private var heroAnimationPlayers: [String: SCNAnimationPlayer] = [:]
    private var currentHeroAnimation: HeroAnimationState = .idle
    private var heroAttackAnimationTime: Float = 0
    private var heroDamageAnimationTime: Float = 0
    private var heroSkillAnimationTime: Float = 0
    private var cameraDistance: Float = 26
    private var cameraHeight: Float = 16
    private var cameraPitch: Float = 0.93
    private var cameraYaw: Float = .pi / 4
    private var cameraZoom: Float = 1.0
    private var desiredCameraZoom: Float = 1.0
    private let minZoom: Float = 0.7
    private let maxZoom: Float = 1.4
    private var cameraPanInput = SIMD2<Float>(repeating: 0)
    private var cameraPanOffset = SIMD2<Float>(repeating: 0)
    
    private var minimapCache = MinimapState(hero: nil, heroRotation: nil, objects: [], halfSize: mapHalfSize)
    
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var gameTime: Float = 0.0 // Игровое время для мобов
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
    private var daylightFactor: Float = 1.0
    
    // Item Inventory
    var inventory: [ItemSlot] = [
        ItemSlot(type: .tango, count: 3),
        ItemSlot(type: .clarity, count: 1),
        ItemSlot(type: .ironBranch, count: 1),
        ItemSlot(type: .faerieFire, count: 1),
        ItemSlot(type: .empty, count: 0),
        ItemSlot(type: .empty, count: 0)
    ]
    
    init(sceneView: SCNView) {
        super.init()
        
        // Создаем сцену
        scene = SCNScene()
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor.black
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        
        // Настраиваем камеру
        setupCamera()
        
        // Настраиваем освещение
        setupLighting()
        
        // Создаем землю
        setupGround()
        
        // Загружаем модель героя
        loadHero()
        
        // Загружаем мобов
        loadMobs()
        
        // Создаем декоративные объекты
        createDecorativeObjects()
        
        // Инициализируем способности
        initializeAbilities()
        
        // Настраиваем обновление сцены
        sceneView.delegate = self
        sceneView.isPlaying = true
        
        // Инициализируем игровое состояние
        humans = [CharacterInstance(position: SIMD3<Float>(0, groundY, 0),
                                    rotation: 0,
                                    velocity: SIMD3<Float>(repeating: 0),
                                    scale: 1,
                                    lastStepTime: 0)]
        
        rebuildMinimapCache()
    }
    
    private func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 200
        
        cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        
        updateCameraPosition()
    }
    
    private func setupLighting() {
        // Основное направленное освещение (солнце)
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.color = UIColor(white: 0.95, alpha: 1.0)
        sunLight.intensity = 1000
        sunLight.castsShadow = true
        sunLight.shadowRadius = 10
        sunLight.shadowColor = UIColor(white: 0, alpha: 0.3)
        
        let sunNode = SCNNode()
        sunNode.light = sunLight
        sunNode.position = SCNVector3(0, 80, 0)
        sunNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sunNode)
        
        // Окружающее освещение
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.4, alpha: 1.0)
        ambientLight.intensity = 500
        
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Освещение от героя (точечный источник)
        let heroLight = SCNLight()
        heroLight.type = .omni
        heroLight.color = UIColor(red: 1.0, green: 0.85, blue: 0.65, alpha: 1.0)
        heroLight.intensity = 500
        heroLight.attenuationStartDistance = 5
        heroLight.attenuationEndDistance = 18
        
        let heroLightNode = SCNNode()
        heroLightNode.light = heroLight
        heroLightNode.position = SCNVector3(0, 3, 0)
        scene.rootNode.addChildNode(heroLightNode)
    }
    
    private func setupGround() {
        let groundGeometry = SCNPlane(width: 100, height: 100)
        // SCNPlane doesn't have segmentCount property - it's automatically tessellated
        
        // Загружаем текстуру земли
        let groundMaterial = SCNMaterial()
        if let terrainURL = Bundle.main.url(forResource: "terrain", withExtension: "jpg", subdirectory: "Resources/Images") {
            groundMaterial.diffuse.contents = terrainURL
        } else {
            let directPath = "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Images/terrain.jpg"
            if FileManager.default.fileExists(atPath: directPath) {
                groundMaterial.diffuse.contents = URL(fileURLWithPath: directPath)
            } else {
                groundMaterial.diffuse.contents = UIColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1.0)
            }
        }
        groundMaterial.diffuse.wrapS = .repeat
        groundMaterial.diffuse.wrapT = .repeat
        groundMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
        
        groundGeometry.materials = [groundMaterial]
        
        groundNode = SCNNode(geometry: groundGeometry)
        groundNode.position = SCNVector3(0, groundY, 0)
        groundNode.rotation = SCNVector4(1, 0, 0, -Float.pi / 2)
        scene.rootNode.addChildNode(groundNode)
    }
    
    private func loadHero() {
        let albedoURL = URL(fileURLWithPath: "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Models/Heroes/Albedo.usdz")
        
        // Пробуем загрузить из Bundle
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "Albedo", withExtension: "usdz", subdirectory: "Resources/Models/Heroes"),
            Bundle.main.url(forResource: "Albedo", withExtension: "usdz", subdirectory: "Resources/Models"),
            Bundle.main.url(forResource: "Albedo", withExtension: "usdz"),
            albedoURL
        ]
        
        var loadedNode: SCNNode?
        var loadedScene: SCNScene?
        
        for case let url? in possibleURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let scene = try SCNScene(url: url, options: nil)
                    loadedScene = scene
                    
                    // Ищем корневой узел или первый узел с геометрией
                    scene.rootNode.enumerateChildNodes { (node, _) in
                        if loadedNode == nil && (node.geometry != nil || !node.childNodes.isEmpty) {
                            loadedNode = node
                        }
                    }
                    
                    if loadedNode == nil {
                        loadedNode = scene.rootNode
                    }
                    
                    if loadedNode != nil {
                        print("✅ Loaded Albedo hero model from: \(url.path)")
                        break
                    }
                } catch {
                    print("⚠️ Failed to load Albedo model from \(url.path): \(error)")
                }
            }
        }
        
        if let heroModelNode = loadedNode, let heroScene = loadedScene {
            heroNode = heroModelNode.clone()
            heroNode?.scale = SCNVector3(heroScale, heroScale, heroScale)
            heroNode?.position = SCNVector3(0, groundY + 1.0 * heroScale, 0)
            
            // Загружаем анимации из сцены
            loadHeroAnimations(from: heroScene)
            
            scene.rootNode.addChildNode(heroNode!)
            
            // Запускаем idle анимацию по умолчанию
            playHeroAnimation(.idle, loop: true)
            
            print("✅ Albedo hero node added to scene with animations")
        } else {
            // Fallback - простая коробка
            let boxGeometry = SCNBox(width: 1, height: 2, length: 1, chamferRadius: 0)
            let boxMaterial = SCNMaterial()
            boxMaterial.diffuse.contents = UIColor.blue
            boxGeometry.materials = [boxMaterial]
            
            heroNode = SCNNode(geometry: boxGeometry)
            heroNode?.position = SCNVector3(0, groundY + 1, 0)
            scene.rootNode.addChildNode(heroNode!)
            print("⚠️ Using fallback hero geometry")
        }
        
        // Создаем платформу под героем
        let platformGeometry = SCNPlane(width: CGFloat(heroPlatformRadius * 2 * heroScale),
                                       height: CGFloat(heroPlatformRadius * 2 * heroScale))
        let platformMaterial = SCNMaterial()
        platformMaterial.diffuse.contents = UIColor(red: 0.2, green: 0.7, blue: 0.8, alpha: 0.7)
        platformGeometry.materials = [platformMaterial]
        
        heroPlatformNode = SCNNode(geometry: platformGeometry)
        heroPlatformNode?.position = SCNVector3(0, groundY + 0.02, 0)
        heroPlatformNode?.rotation = SCNVector4(1, 0, 0, -Float.pi / 2)
        scene.rootNode.addChildNode(heroPlatformNode!)
    }
    
    private func loadHeroAnimations(from scene: SCNScene) {
        // Загружаем все анимации из сцены USDZ
        // В USDZ файлах анимации могут быть встроены в сцену
        
        // Функция для рекурсивного поиска анимаций
        func findAnimations(in node: SCNNode) {
            // Проверяем анимации текущего узла
            for key in node.animationKeys {
                if let animationPlayer = node.animationPlayer(forKey: key) {
                    let animationName = key.lowercased()
                    // Сохраняем ссылку на анимацию (USDZ анимации можно использовать напрямую)
                    heroAnimationPlayers[animationName] = animationPlayer
                    print("✅ Found animation: \(key)")
                }
            }
            
            // Рекурсивно проверяем дочерние узлы
            for childNode in node.childNodes {
                findAnimations(in: childNode)
            }
        }
        
        // Ищем анимации в корневом узле и всех дочерних
        findAnimations(in: scene.rootNode)
        
        // Также проверяем анимации самой сцены
        if let animationPlayer = scene.rootNode.animationPlayer(forKey: "animation") {
            heroAnimationPlayers["animation"] = animationPlayer
            print("✅ Found scene animation")
        }
        
        // Пробуем найти анимации по известным именам в разных узлах
        let knownAnimationNames = [
            "dvl_mdl_albedo_idle_00",
            "dvl_mdl_albedo_attack",
            "dvl_mdl_albedo_damage",
            "dvl_mdl_albedo_dead",
            "dvl_mdl_albedo_skill",
            "dvl_mdl_albedo_spskill_00"
        ]
        
        // Ищем анимации в корневом узле
        for animName in knownAnimationNames {
            if let player = scene.rootNode.animationPlayer(forKey: animName) {
                heroAnimationPlayers[animName.lowercased()] = player
                print("✅ Found known animation in root: \(animName)")
            }
        }
        
        // Ищем анимации в дочерних узлах
        scene.rootNode.enumerateChildNodes { (node, _) in
            for animName in knownAnimationNames {
                if let player = node.animationPlayer(forKey: animName) {
                    heroAnimationPlayers[animName.lowercased()] = player
                    print("✅ Found known animation in child: \(animName)")
                }
            }
        }
        
        print("📊 Total animations loaded: \(heroAnimationPlayers.count)")
    }
    
    private func playHeroAnimation(_ state: HeroAnimationState, loop: Bool = false) {
        guard let heroNode = heroNode else { return }
        
        // Останавливаем текущую анимацию
        heroNode.removeAllAnimations()
        
        let animationName: String
        switch state {
        case .idle:
            animationName = "dvl_mdl_albedo_idle_00"
        case .walking:
            animationName = "dvl_mdl_albedo_idle_00" // Используем idle для ходьбы, если нет отдельной
        case .attacking:
            animationName = "dvl_mdl_albedo_attack"
        case .takingDamage:
            animationName = "dvl_mdl_albedo_damage"
        case .dead:
            animationName = "dvl_mdl_albedo_dead"
        case .usingSkill:
            animationName = "dvl_mdl_albedo_skill"
        case .usingSpecialSkill:
            animationName = "dvl_mdl_albedo_spskill_00"
        }
        
        // Ищем анимацию по имени (пробуем разные варианты)
        var foundAnimation: SCNAnimationPlayer?
        
        // Прямое совпадение
        if let player = heroAnimationPlayers[animationName.lowercased()] {
            foundAnimation = player
        } else {
            // Ищем частичное совпадение
            for (key, player) in heroAnimationPlayers {
                if key.contains(animationName.lowercased()) || animationName.lowercased().contains(key) {
                    foundAnimation = player
                    break
                }
            }
        }
        
        if let animationPlayer = foundAnimation {
            // Получаем анимацию из player и клонируем для настройки
            let sourceAnimation = animationPlayer.animation
            let clonedAnimation = sourceAnimation.copy() as! SCNAnimation
            
            // Настраиваем параметры анимации (repeatCount использует CGFloat)
            clonedAnimation.repeatCount = loop ? CGFloat.infinity : CGFloat(1.0)
            clonedAnimation.isRemovedOnCompletion = !loop
            
            // Создаем новый player с настроенной анимацией
            let newPlayer = SCNAnimationPlayer(animation: clonedAnimation)
            heroNode.addAnimationPlayer(newPlayer, forKey: "currentAnimation")
            newPlayer.play()
            
            currentHeroAnimation = state
            print("🎬 Playing animation: \(animationName) (state: \(state))")
        } else {
            print("⚠️ Animation not found: \(animationName), available: \(heroAnimationPlayers.keys.joined(separator: ", "))")
        }
    }
    
    // Текстуры для Albedo уже встроены в USDZ файл, не требуется ручное применение
    
    private func loadMobs() {
        let wyvernURL = URL(fileURLWithPath: "/Users/digkill/Projects/swift/ARPG/ARPG/ARPG/Resources/Models/mobs/rb/Wyvern_animated.usdz")
        
        // Пробуем загрузить из Bundle
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz", subdirectory: "Resources/Models/mobs/rb"),
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz", subdirectory: "Resources/Models/mobs"),
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz"),
            wyvernURL
        ]
        
        var wyvernNode: SCNNode?
        for case let url? in possibleURLs {
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let scene = try SCNScene(url: url, options: nil)
                    
                    // Ищем корневой узел или первый узел с геометрией
                    scene.rootNode.enumerateChildNodes { (node, _) in
                        if wyvernNode == nil {
                            wyvernNode = node
                        }
                    }
                    
                    if wyvernNode == nil {
                        wyvernNode = scene.rootNode
                    }
                    
                    if wyvernNode != nil {
                        print("✅ Loaded Wyvern dragon from: \(url.path)")
                        break
                    }
                } catch {
                    print("⚠️ Failed to load Wyvern from \(url.path): \(error)")
                }
            }
        }
        
        if let dragonNode = wyvernNode {
            // Создаем копию узла для моба
            let mobNode = dragonNode.clone()
            
            // Мощный дракон: 10k HP, 5k MP, 15k урон (CP), атака 255 по площади
            let dragonPosition = SIMD3<Float>(20, groundY + 10, 20) // Позиция на карте
            let dragonScale: Float = 0.05 // Большой размер
            
            mobNode.scale = SCNVector3(dragonScale, dragonScale, dragonScale)
            mobNode.position = SCNVector3(dragonPosition.x, dragonPosition.y, dragonPosition.z)
            
            // Воспроизводим анимацию, если есть
            if let animationPlayer = mobNode.animationPlayer(forKey: "animation") {
                animationPlayer.play()
            } else {
                // Ищем анимации в дочерних узлах
                mobNode.enumerateChildNodes { (node, _) in
                    if let animationPlayer = node.animationPlayer(forKey: "animation") {
                        animationPlayer.play()
                    }
                }
            }
            
            let dragon = Mob(
                node: mobNode,
                position: dragonPosition,
                rotation: 0,
                velocity: SIMD3<Float>(0, 0, 0),
                maxHealth: 10000,
                health: 10000,
                maxMana: 5000,
                mana: 5000,
                attackDamage: 15000, // 15k урон (CP)
                attackRange: 255, // Атака по площади 255
                attackCooldown: 2.0, // Атака каждые 2 секунды
                lastAttackTime: 0,
                aggroRange: 50.0, // Очень большой радиус агрессии
                isAggressive: true,
                scale: dragonScale
            )
            
            mobs.append(dragon)
            scene.rootNode.addChildNode(mobNode)
            print("✅ Wyvern dragon added to scene with stats: HP=10k, MP=5k, Damage=15k, Range=255")
        } 
    }
    
    private func createDecorativeObjects() {
        decorativeObjects = []
        for _ in 0..<80 {
            let x = Float.random(in: -mapHalfSize...mapHalfSize)
            let z = Float.random(in: -mapHalfSize...mapHalfSize)
            let scale = Float.random(in: 0.6...1.5)
            decorativeObjects.append(DecorativeObject(position: SIMD3<Float>(x, groundY, z), scale: scale))
            
            let boxGeometry = SCNBox(width: 1, height: 1.5, length: 1, chamferRadius: 0)
            let boxMaterial = SCNMaterial()
            boxMaterial.diffuse.contents = UIColor(red: 0.35, green: 0.3, blue: 0.26, alpha: 1.0)
            boxGeometry.materials = [boxMaterial]
            
            let boxNode = SCNNode(geometry: boxGeometry)
            boxNode.position = SCNVector3(x, groundY, z)
            boxNode.scale = SCNVector3(scale, scale, scale)
            scene.rootNode.addChildNode(boxNode)
        }
    }
    
    private func updateHeroAnimations(deltaTime: Float, hero: CharacterInstance) {
        // Проверяем состояние героя и переключаем анимации
        
        // Если герой мертв - не меняем анимацию
        if heroStats.health <= 0 {
            if currentHeroAnimation != .dead {
                playHeroAnimation(.dead, loop: false)
            }
            return
        }
        
        // Обновляем таймеры анимаций
        heroAttackAnimationTime = max(0, heroAttackAnimationTime - deltaTime)
        heroDamageAnimationTime = max(0, heroDamageAnimationTime - deltaTime)
        heroSkillAnimationTime = max(0, heroSkillAnimationTime - deltaTime)
        
        // Если идет анимация атаки - не переключаем
        if heroAttackAnimationTime > 0 {
            return
        }
        
        // Если идет анимация получения урона - не переключаем
        if heroDamageAnimationTime > 0 {
            return
        }
        
        // Если идет анимация способности - не переключаем
        if heroSkillAnimationTime > 0 {
            return
        }
        
        // Проверяем движение
        let isMoving = simd_length(hero.velocity) > 0.1
        
        // Проверяем атаку
        if InputManager.shared.isAttackPressed && currentHeroAnimation != .attacking {
            playHeroAnimation(.attacking, loop: false)
            heroAttackAnimationTime = 1.0 // Длительность анимации атаки
            return
        }
        
        // Переключаем между idle и walking
        if isMoving {
            if currentHeroAnimation != .walking {
                playHeroAnimation(.walking, loop: true)
            }
        } else {
            if currentHeroAnimation != .idle {
                playHeroAnimation(.idle, loop: true)
            }
        }
    }
    
    private func initializeAbilities() {
        abilities[.qAvalanche] = Ability(name: "Avalanche", manaCost: 90, cooldown: 17, currentCooldown: 0, castRange: 10, description: "Causes an avalanche")
        abilities[.wToss] = Ability(name: "Toss", manaCost: 120, cooldown: 8, currentCooldown: 0, castRange: 5, description: "Tosses a unit")
        abilities[.eTreeGrab] = Ability(name: "Tree Grab", manaCost: 0, cooldown: 0, currentCooldown: 0, castRange: 2, description: "Grabs a tree")
        abilities[.rGrow] = Ability(name: "Grow", manaCost: 0, cooldown: 0, currentCooldown: 0, castRange: 0, description: "Increases size")
    }
    
    // MARK: - Hero Actions
    
    func performHeroAttack() {
        guard heroStats.health > 0 else { return }
        
        // Играем анимацию атаки
        playHeroAnimation(.attacking, loop: false)
        heroAttackAnimationTime = 1.0
        
        // Находим ближайшего врага в радиусе атаки
        let heroPos = humans.first?.position ?? SIMD3<Float>(0, 0, 0)
        let attackRange: Float = 2.5
        
        for i in 0..<mobs.count {
            let mobPos = mobs[i].position
            let distance = simd_length(heroPos - mobPos)
            
            if distance <= attackRange {
                // Наносим урон мобу
                mobs[i].health = max(0, mobs[i].health - heroStats.baseDamage)
                print("⚔️ Hero attacks! Mob takes \(heroStats.baseDamage) damage! Mob HP: \(mobs[i].health)/\(mobs[i].maxHealth)")
                
                // Звук атаки
                SoundManager.shared.playSound(name: "attack", fileExtension: "mp3", volume: 0.6)
                break
            }
        }
    }
    
    func castAbility(_ key: AbilityKey, targetPos: SIMD3<Float>? = nil) {
        guard let hero = humans.first,
              var ability = abilities[key],
              ability.currentCooldown <= 0,
              heroStats.mana >= ability.manaCost,
              heroStats.health > 0 else { return }
        
        heroStats.mana -= ability.manaCost
        ability.currentCooldown = ability.cooldown
        abilities[key] = ability
        
        // Определяем тип способности для анимации
        let isSpecialSkill = (key == .rGrow) // Ультимейт использует специальную анимацию
        
        if isSpecialSkill {
            playHeroAnimation(.usingSpecialSkill, loop: false)
            heroSkillAnimationTime = 2.0
        } else {
            playHeroAnimation(.usingSkill, loop: false)
            heroSkillAnimationTime = 1.5
        }
        
        // Выполняем способность
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
    
    func takeDamage(_ damage: Float) {
        guard heroStats.health > 0 else { return }
        
        heroStats.health = max(0, heroStats.health - damage)
        
        // Играем анимацию получения урона
        playHeroAnimation(.takingDamage, loop: false)
        heroDamageAnimationTime = 0.5
        
        // Если здоровье закончилось - играем анимацию смерти
        if heroStats.health <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playHeroAnimation(.dead, loop: false)
            }
        }
        
        print("💥 Hero takes \(damage) damage! HP: \(heroStats.health)/\(heroStats.maxHealth)")
    }
    
    private func castAvalanche(targetPos: SIMD3<Float>) {
        // Реализация способности Avalanche
        let radius: Float = 5.0
        let damage: Float = 150
        
        for i in 0..<mobs.count {
            let mobPos = mobs[i].position
            let distance = simd_length(targetPos - mobPos)
            
            if distance <= radius {
                mobs[i].health = max(0, mobs[i].health - damage)
            }
        }
    }
    
    private func castToss(targetPos: SIMD3<Float>) {
        // Реализация способности Toss
        print("🎯 Toss cast at \(targetPos)")
    }
    
    private func castTreeGrab() {
        // Реализация способности Tree Grab
        heroStats.hasTree = true
        heroStats.treeBonusDamage = 20
        print("🌳 Tree grabbed! Bonus damage: +\(heroStats.treeBonusDamage)")
    }
    
    private func castGrow() {
        // Реализация способности Grow
        heroStats.growMultiplier += 0.1
        heroScale *= 1.1
        if let heroNode = heroNode {
            heroNode.scale = SCNVector3(heroScale, heroScale, heroScale)
        }
        print("📈 Grow! Size multiplier: \(heroStats.growMultiplier)")
    }
    
    // MARK: - Game State Updates
    
    func updateGameState(deltaTime: Float) {
        guard !humans.isEmpty else { return }
        var hero = humans[0]
        let input = InputManager.shared.moveDirection
        
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
        
        // Обновляем позицию героя в сцене
        if let heroNode = heroNode {
            heroNode.position = SCNVector3(hero.position.x, hero.position.y + 1.0 * heroScale, hero.position.z)
            heroNode.rotation = SCNVector4(0, 1, 0, hero.rotation)
        }
        
        // Обновляем анимации героя
        updateHeroAnimations(deltaTime: deltaTime, hero: hero)
        
        // Обновляем освещение от героя
        if let heroLightNode = scene.rootNode.childNodes.first(where: { $0.light?.type == .omni }) {
            heroLightNode.position = SCNVector3(hero.position.x, hero.position.y + 3, hero.position.z)
        }
        
        // Обновляем игровое время
        gameTime += deltaTime
        
        // Обрабатываем атаку героя
        if InputManager.shared.isAttackPressed {
            performHeroAttack()
        }
        
        // Обрабатываем способности
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
        
        updateCameraMatrices()
        updateAbilities(deltaTime: deltaTime)
        updateInventory(deltaTime: deltaTime)
        updateDayNightCycle(deltaTime: deltaTime)
        updateMobs(deltaTime: deltaTime)
        rebuildMinimapCache()
    }
    
    private func updateCameraMatrices() {
        guard let hero = humans.first else { return }
        
        let maxPanDistance: Float = cameraDistance * 0.55
        let desiredPanOffset = SIMD2<Float>(cameraPanInput.x * maxPanDistance,
                                            cameraPanInput.y * maxPanDistance)
        cameraPanOffset = simd_mix(cameraPanOffset,
                                   desiredPanOffset,
                                   SIMD2<Float>(repeating: 0.12))
        
        cameraZoom += (desiredCameraZoom - cameraZoom) * 0.08
        cameraZoom = min(max(cameraZoom, minZoom), maxZoom)
        
        var desiredTarget = hero.position + SIMD3<Float>(0, 1.2, 0)
        desiredTarget.x += cameraPanOffset.x
        desiredTarget.z += cameraPanOffset.y
        desiredTarget.x = min(max(desiredTarget.x, -mapHalfSize + 6), mapHalfSize - 6)
        desiredTarget.z = min(max(desiredTarget.z, -mapHalfSize + 6), mapHalfSize - 6)
        
        updateCameraPosition(target: desiredTarget)
    }
    
    private func updateCameraPosition(target: SIMD3<Float> = SIMD3<Float>(0, 4, 0)) {
        let zoomedDistance = cameraDistance * cameraZoom
        let horizontalDistance = cos(cameraPitch) * zoomedDistance
        let verticalOffset = sin(cameraPitch) * zoomedDistance + cameraHeight
        
        let offset = SIMD3<Float>(-sin(cameraYaw) * horizontalDistance,
                                  verticalOffset,
                                  -cos(cameraYaw) * horizontalDistance)
        let desiredPosition = target + offset
        
        cameraNode.position = SCNVector3(desiredPosition.x, desiredPosition.y, desiredPosition.z)
        cameraNode.look(at: SCNVector3(target.x, target.y, target.z))
    }
    
    private func updateAbilities(deltaTime: Float) {
        // Copy keys to avoid overlapping access
        let keys = Array(abilities.keys)
        for key in keys {
            if var ability = abilities[key] {
                ability.currentCooldown = max(0, ability.currentCooldown - deltaTime)
                abilities[key] = ability
            }
        }
        
        activeEffects = activeEffects.filter { effect in
            var updated = effect
            updated.timeRemaining -= deltaTime
            return updated.timeRemaining > 0
        }
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
    
    private func updateDayNightCycle(deltaTime: Float) {
        dayNightTime += deltaTime
        if dayNightTime > dayNightDuration {
            dayNightTime -= dayNightDuration
        }
        daylightFactor = 0.5 + 0.5 * cos(dayNightTime / dayNightDuration * 2 * Float.pi)
    }
    
    private func updateMobs(deltaTime: Float) {
        // Мобы двигаются независимо от героя
        for i in 0..<mobs.count {
            var mob = mobs[i]
            
            // Простое патрулирование или статичное положение
            // Дракон остается на месте или двигается по своему паттерну
            if mob.isAggressive {
                // Можно добавить патрулирование или другие паттерны движения
                // Пока оставляем дракона на месте
                mob.velocity *= 0.9 // Постепенно останавливаемся
                mob.position += mob.velocity * deltaTime
                mob.position.y = groundY + 3 // Дракон летает немного выше земли
            }
            
            // Обновляем позицию и поворот в сцене
            mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
            mob.node.rotation = SCNVector4(0, 1, 0, mob.rotation)
            
            // Регенерация маны
            mob.mana = min(mob.maxMana, mob.mana + 10 * deltaTime)
            
            mobs[i] = mob
        }
    }
    
    private func performMobAttack(mob: inout Mob, heroPosition: SIMD3<Float>) {
        // Атака по площади - наносим урон всем в радиусе attackRange (255)
        // НЕ связана с позицией героя - атака происходит независимо
        let attackCenter = mob.position
        let attackRadius = mob.attackRange
        
        // Проверяем всех в радиусе атаки (включая героя, если он рядом)
        if let hero = humans.first {
            let heroDistance = simd_length(hero.position - attackCenter)
            if heroDistance <= attackRadius {
                // Наносим урон герою через систему получения урона (с анимацией)
                takeDamage(mob.attackDamage)
                print("🐉 Wyvern attacks! Hero takes \(mob.attackDamage) damage!")
            }
        }
        
        // Проверяем других мобов в радиусе (если будут добавлены)
        for i in 0..<mobs.count {
            if i < mobs.count {
                let otherMobPos = mobs[i].position
                let otherDistance = simd_length(otherMobPos - attackCenter)
                // Не атакуем себя
                if otherDistance > 0.1 && otherDistance <= attackRadius {
                    mobs[i].health = max(0, mobs[i].health - mob.attackDamage * 0.5) // Мобы получают 50% урона
                }
            }
        }
        
        // Визуальный эффект атаки удален по запросу
        
        // Звук мощной атаки
        SoundManager.shared.playSound(name: "attack", fileExtension: "mp3", volume: 1.0)
    }
    
    private func rebuildMinimapCache() {
        let hero2D = humans.first.map { SIMD2<Float>($0.position.x, $0.position.z) }
        let heroRot = humans.first?.rotation
        let objects2D = decorativeObjects.map { SIMD2<Float>($0.position.x, $0.position.z) }
        minimapCache = MinimapState(hero: hero2D, heroRotation: heroRot, objects: objects2D, halfSize: mapHalfSize)
    }
    
    // MARK: - Public API
    
    func getFPS() -> Int {
        return reportedFPS
    }
    
    func getMinimapData() -> MinimapState {
        return minimapCache
    }
    
    func adjustCameraZoom(by delta: Float) {
        desiredCameraZoom = min(max(desiredCameraZoom + delta, minZoom), maxZoom)
    }
    
    func centerCameraOnHero() {
        cameraPanInput = SIMD2<Float>(repeating: 0)
    }
}

// MARK: - SCNSceneRendererDelegate

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

