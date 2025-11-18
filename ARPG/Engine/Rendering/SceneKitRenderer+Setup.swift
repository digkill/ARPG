//
//  SceneKitRenderer+Setup.swift
//  ARPG
//
//  Created by Digkill on 18.11.2025.
//

import SceneKit
import SceneKit.ModelIO
import UIKit
import ModelIO

extension SceneKitRenderer {
    func setupCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 60
        camera.zNear = 0.1
        camera.zFar = 200
        
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        
        updateCameraPosition(target: SIMD3<Float>(0, 4, 0))
    }
    
    func setupLighting() {
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
        
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.4, alpha: 1.0)
        ambientLight.intensity = 500
        
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
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
    
    func setupGround() {
        let groundGeometry = SCNPlane(width: 100, height: 100)
        let groundMaterial = SCNMaterial()
        if let terrainURL = Bundle.main.url(forResource: "terrain", withExtension: "jpg", subdirectory: "Resources/Images") {
            groundMaterial.diffuse.contents = terrainURL
        } else if let directPath = Bundle.main.url(forResource: "terrain", withExtension: "jpg", subdirectory: nil) {
            groundMaterial.diffuse.contents = directPath
        } else {
            groundMaterial.diffuse.contents = UIColor(red: 0.3, green: 0.5, blue: 0.2, alpha: 1.0)
        }
        groundMaterial.diffuse.wrapS = .repeat
        groundMaterial.diffuse.wrapT = .repeat
        groundMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(10, 10, 1)
        groundGeometry.materials = [groundMaterial]
        
        let groundNode = SCNNode(geometry: groundGeometry)
        groundNode.position = SCNVector3(0, WorldConstants.groundY, 0)
        groundNode.rotation = SCNVector4(1, 0, 0, -Float.pi / 2)
        scene.rootNode.addChildNode(groundNode)
    }
    
    func loadScene(from url: URL) throws -> SCNScene {
        let ext = url.pathExtension.lowercased()
        let requiresModelIO = ["glb", "gltf", "fbx", "obj"].contains(ext)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Файл не найден: \(url.path)"])
        }
        
        if requiresModelIO {
            print("🔄 Импорт через ModelIO: \(url.lastPathComponent)")
            do {
                return try loadSceneUsingModelIO(url: url)
            } catch {
                print("   ⚠️ ModelIO не справился: \(error.localizedDescription)")
                print("   🔁 Пробуем SCNSceneSource...")
                do {
                    return try loadSceneUsingSceneSource(url: url)
                } catch let sourceError {
                    var info = error.localizedDescription
                    info += " | SceneSource: \(sourceError.localizedDescription)"
                    throw NSError(domain: "SceneKitError", code: -1, userInfo: [
                        NSLocalizedDescriptionKey: "Не удалось импортировать \(url.lastPathComponent): \(info)"
                    ])
                }
            }
        }
        
        return try SCNScene(url: url, options: [
            .animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly
        ])
    }
    
    private func loadSceneUsingModelIO(url: URL) throws -> SCNScene {
        let asset = MDLAsset(url: url)
        let objects = asset.childObjects(of: MDLObject.self)
        guard !objects.isEmpty else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelIO не обнаружил объектов в \(url.lastPathComponent)"])
        }
        
        let scene = SCNScene()
        for object in objects {
            let node = SCNNode(mdlObject: object)
            scene.rootNode.addChildNode(node)
        }
        
        guard !scene.rootNode.childNodes.isEmpty else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Сцена из \(url.lastPathComponent) пуста после импорта ModelIO"])
        }
        return scene
    }
    
    private func loadSceneUsingSceneSource(url: URL) throws -> SCNScene {
        guard let source = SCNSceneSource(url: url, options: nil) else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "SCNSceneSource не смог открыть \(url.lastPathComponent)"])
        }
        guard let scene = source.scene(options: nil) else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "SCNSceneSource не вернул сцену для \(url.lastPathComponent)"])
        }
        guard !scene.rootNode.childNodes.isEmpty || scene.rootNode.geometry != nil else {
            throw NSError(domain: "SceneKitError", code: -1, userInfo: [NSLocalizedDescriptionKey: "SCNSceneSource импортировал пустую сцену для \(url.lastPathComponent)"])
        }
        return scene
    }
    
    // MARK: - Hero loading
    
    func loadHero(hero: HeroDefinition? = nil) {
        let heroDefinition = hero ?? selectedHero
        selectedHero = heroDefinition
        
        heroScale = heroDefinition.scale
        
        // Настраиваем характеристики героя
        setupHeroStats(for: heroDefinition)
        
        var url = resolveResourceURL(for: heroDefinition.modelPath)
        
        var finalURL = url
        
        if finalURL == nil, let animationFiles = heroDefinition.animationFilePaths {
            for path in animationFiles.values {
                if let resolved = resolveResourceURL(for: path) {
                    finalURL = resolved
                    print("ℹ️ Используем файл анимации как базовую модель: \(path)")
                    break
                }
            }
        }
        
        guard let readyURL = finalURL else {
            fallbackToDefaultHero(reason: "Файл не найден: \(heroDefinition.modelPath)", failedHero: heroDefinition)
            return
        }
        
        loadHeroFromURL(url: readyURL, heroDefinition: heroDefinition)
    }
    
    private func resolveResourceURL(for path: String) -> URL? {
        let components = path.components(separatedBy: "/")
        guard let fileNameWithExt = components.last else { return nil }
        let fileName = (fileNameWithExt as NSString).deletingPathExtension
        let fileExtension = (fileNameWithExt as NSString).pathExtension
        let subdirectory = components.count > 1 ? components.dropLast().joined(separator: "/") : nil
        
        if let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: nil) {
            return url
        }
        if let bundleRoot = Bundle.main.resourcePath {
            let fullPath = (bundleRoot as NSString).appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fullPath) {
                return URL(fileURLWithPath: fullPath)
            }
        }
        return nil
    }
    
    private func loadHeroFromURL(url: URL, heroDefinition: HeroDefinition) {
        do {
            let loadedScene = try loadScene(from: url)
            
            // Ищем главный узел
            var loadedNode: SCNNode?
            loadedScene.rootNode.enumerateChildNodes { node, _ in
                if loadedNode == nil {
                    let hasGeometry = node.geometry != nil
                    let hasChildren = !node.childNodes.isEmpty
                    if hasGeometry || hasChildren {
                        loadedNode = node
                    }
                }
            }
            
            if loadedNode == nil {
                loadedNode = loadedScene.rootNode
            }
            
            guard let heroModelNode = loadedNode else {
                fallbackToDefaultHero(reason: "Не найден узел модели в \(url.lastPathComponent)", failedHero: heroDefinition)
                return
            }
            
            // Клонируем узел для использования в основной сцене
            heroNode = heroModelNode.clone()
            heroNode?.scale = SCNVector3(heroScale, heroScale, heroScale)
            heroNode?.position = SCNVector3(0, WorldConstants.groundY + heroScale, 0)
            
            // Поворот из HeroDefinition
            let rotation = heroDefinition.rotation
            let needsRotation = rotation.x != 0 || rotation.y != 0 || rotation.z != 0 || rotation.w != 0
            if needsRotation {
                heroNode?.rotation = SCNVector4(rotation.x, rotation.y, rotation.z, rotation.w)
            }
            
            // Загружаем анимации из загруженной сцены
            loadHeroAnimations(from: loadedScene)
            
            // Добавляем узел в основную сцену синхронно (но не во время рендеринга)
            // Это должно быть вызвано из configure(), который вызывается до начала рендеринга
            if let heroNode = heroNode {
                scene.rootNode.addChildNode(heroNode)
            }
            
            // Платформа под героем
            let platformGeometry = SCNPlane(
                width: CGFloat(WorldConstants.heroPlatformRadius * 2 * heroScale),
                height: CGFloat(WorldConstants.heroPlatformRadius * 2 * heroScale)
            )
            let platformMaterial = SCNMaterial()
            platformMaterial.diffuse.contents = UIColor(red: 0.2, green: 0.7, blue: 0.8, alpha: 0.7)
            platformGeometry.materials = [platformMaterial]
            
            let platformNode = SCNNode(geometry: platformGeometry)
            platformNode.position = SCNVector3(0, WorldConstants.groundY + 0.02, 0)
            platformNode.rotation = SCNVector4(1, 0, 0, -Float.pi / 2)
            scene.rootNode.addChildNode(platformNode)
            
            // Запускаем анимацию idle после добавления в сцену
            playHeroAnimation(.idle, loop: true)
            
            print("✅ Герой загружен: \(heroDefinition.displayName) из \(heroDefinition.modelPath)")
        } catch {
            fallbackToDefaultHero(reason: "Ошибка загрузки \(heroDefinition.modelPath): \(error.localizedDescription)", failedHero: heroDefinition)
            return
        }
    }

    private func fallbackToDefaultHero(reason: String, failedHero: HeroDefinition) {
        print("⚠️ \(reason)")
        let defaultHero = HeroRegistry.shared.defaultHero
        if failedHero.identifier != defaultHero.identifier {
            print("➡️ Переключаемся на героя по умолчанию: \(defaultHero.displayName)")
            loadHero(hero: defaultHero)
        } else {
            print("⚠️ Даже герой по умолчанию не доступен. Загружаем заглушку.")
            let placeholder = SCNBox(width: 1.0, height: 2.0, length: 1.0, chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemPink
            placeholder.materials = [material]
            heroNode = SCNNode(geometry: placeholder)
            heroNode?.position = SCNVector3(0, WorldConstants.groundY + 1, 0)
            if let heroNode = heroNode {
                scene.rootNode.addChildNode(heroNode)
            }
        }
    }
    
    // MARK: - Mobs (оставил как было)
    
    func loadMobs() {
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz", subdirectory: "Resources/Models/mobs/rb"),
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz", subdirectory: "Resources/Models/mobs"),
            Bundle.main.url(forResource: "Wyvern_animated", withExtension: "usdz"),
            // Fallback через resourcePath
            Bundle.main.resourcePath.map { URL(fileURLWithPath: ($0 as NSString).appendingPathComponent("Resources/Models/mobs/rb/Wyvern_animated.usdz")) }
        ]
        
        var wyvernNode: SCNNode?
        for case let url? in possibleURLs where FileManager.default.fileExists(atPath: url.path) {
            do {
                let scene = try SCNScene(url: url, options: nil)
                scene.rootNode.enumerateChildNodes { node, _ in
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
        
        guard let dragonNode = wyvernNode else {
            return
        }
        
        let mobNode = dragonNode.clone()
        let dragonPosition = SIMD3<Float>(20, WorldConstants.groundY + 10, 20)
        let dragonScale: Float = 0.05
        
        mobNode.scale = SCNVector3(dragonScale, dragonScale, dragonScale)
        mobNode.position = SCNVector3(dragonPosition.x, dragonPosition.y, dragonPosition.z)
        
        if let animationPlayer = mobNode.animationPlayer(forKey: "animation") {
            animationPlayer.play()
        } else {
            mobNode.enumerateChildNodes { node, _ in
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
            attackDamage: 15000,
            attackRange: 255,
            attackCooldown: 2.0,
            lastAttackTime: 0,
            aggroRange: 50.0,
            isAggressive: true,
            scale: dragonScale
        )
        
        mobs.append(dragon)
        scene.rootNode.addChildNode(mobNode)
        
        loadCows()
    }
    
    private func loadCows() {
        let possibleURLs: [URL?] = [
            Bundle.main.url(forResource: "Cow", withExtension: "usdz", subdirectory: "Resources/Models/mobs/neutral"),
            Bundle.main.url(forResource: "Cow", withExtension: "usdz", subdirectory: "Resources/Models/mobs"),
            Bundle.main.url(forResource: "Cow", withExtension: "usdz"),
            // Fallback через resourcePath
            Bundle.main.resourcePath.map { URL(fileURLWithPath: ($0 as NSString).appendingPathComponent("Resources/Models/mobs/neutral/Cow.usdz")) }
        ]
        
        var cowTemplateNode: SCNNode?
        for case let url? in possibleURLs where FileManager.default.fileExists(atPath: url.path) {
            do {
                let scene = try SCNScene(url: url, options: nil)
                scene.rootNode.enumerateChildNodes { node, _ in
                    if cowTemplateNode == nil {
                        cowTemplateNode = node
                    }
                }
                if cowTemplateNode == nil {
                    cowTemplateNode = scene.rootNode
                }
                if cowTemplateNode != nil {
                    print("✅ Loaded Cow model from: \(url.path)")
                    break
                }
            } catch {
                print("⚠️ Failed to load Cow from \(url.path): \(error)")
            }
        }
        
        guard let cowNodeTemplate = cowTemplateNode else {
            print("⚠️ Cow model not found, skipping cows")
            return
        }
        
        let cowPositions: [SIMD3<Float>] = [
            SIMD3<Float>(-15, WorldConstants.groundY, -15),
            SIMD3<Float>(15, WorldConstants.groundY, -15),
            SIMD3<Float>(-15, WorldConstants.groundY, 15),
            SIMD3<Float>(15, WorldConstants.groundY, 15),
            SIMD3<Float>(-25, WorldConstants.groundY, 0),
            SIMD3<Float>(25, WorldConstants.groundY, 0),
            SIMD3<Float>(0, WorldConstants.groundY, -25),
            SIMD3<Float>(0, WorldConstants.groundY, 25)
        ]
        
        let cowScale: Float = 2.0
        
        for position in cowPositions {
            let cowNode = cowNodeTemplate.clone()
            cowNode.scale = SCNVector3(cowScale, cowScale, cowScale)
            cowNode.position = SCNVector3(position.x, position.y, position.z)
            
            if let animationPlayer = cowNode.animationPlayer(forKey: "animation") {
                animationPlayer.play()
            } else {
                cowNode.enumerateChildNodes { node, _ in
                    if let animationPlayer = node.animationPlayer(forKey: "animation") {
                        animationPlayer.play()
                    }
                }
            }
            
            let cow = Mob(
                node: cowNode,
                position: position,
                rotation: Float.random(in: 0...(2 * Float.pi)),
                velocity: SIMD3<Float>(0, 0, 0),
                maxHealth: 100,
                health: 100,
                maxMana: 0,
                mana: 0,
                attackDamage: 0,
                attackRange: 0,
                attackCooldown: 0,
                lastAttackTime: 0,
                aggroRange: 0,
                isAggressive: false,
                scale: cowScale
            )
            
            mobs.append(cow)
            scene.rootNode.addChildNode(cowNode)
        }
        
        print("✅ Added \(cowPositions.count) cows to the map")
    }
    
    func createDecorativeObjects() {
        decorativeObjects.removeAll()
        for _ in 0..<80 {
            let x = Float.random(in: -WorldConstants.mapHalfSize...WorldConstants.mapHalfSize)
            let z = Float.random(in: -WorldConstants.mapHalfSize...WorldConstants.mapHalfSize)
            let scale = Float.random(in: 0.6...1.5)
            decorativeObjects.append(DecorativeObject(position: SIMD3<Float>(x, WorldConstants.groundY, z), scale: scale))
            
            let boxGeometry = SCNBox(width: 1, height: 1.5, length: 1, chamferRadius: 0)
            let boxMaterial = SCNMaterial()
            boxMaterial.diffuse.contents = UIColor(red: 0.35, green: 0.3, blue: 0.26, alpha: 1.0)
            boxGeometry.materials = [boxMaterial]
            
            let boxNode = SCNNode(geometry: boxGeometry)
            boxNode.position = SCNVector3(x, WorldConstants.groundY, z)
            boxNode.scale = SCNVector3(scale, scale, scale)
            scene.rootNode.addChildNode(boxNode)
        }
    }
    
    func setupHeroStats(for hero: HeroDefinition) {
        switch hero.identifier {
        case "abyssus":
            // Abyssus - Strength hero, ближний бой
            heroStats.strength = 25
            heroStats.agility = 16
            heroStats.intelligence = 18
            heroStats.baseDamage = 56 // 52-60 среднее
            heroStats.attackRange = 1.5 // Ближний бой
            heroStats.maxHealth = 600 + (heroStats.strength * 20) // ~1100 HP
            heroStats.health = heroStats.maxHealth
            heroStats.maxMana = 300 + (heroStats.intelligence * 12) // ~516 MP
            heroStats.mana = heroStats.maxMana
        default:
            // Стандартные характеристики для других героев
            heroStats.strength = 22
            heroStats.agility = 10
            heroStats.intelligence = 14
            heroStats.baseDamage = 50
            heroStats.attackRange = 2.5
            heroStats.maxHealth = 600
            heroStats.health = heroStats.maxHealth
            heroStats.maxMana = 300
            heroStats.mana = heroStats.maxMana
        }
    }
    
    func initializeAbilities() {
        // Очищаем старые способности
        abilities.removeAll()
        
        // Инициализируем способности в зависимости от выбранного героя
        switch selectedHero.identifier {
        case "abyssus":
            // Abyssus abilities
            abilities[.qRiftCleaver] = Ability(name: "Rift Cleaver", manaCost: 100, cooldown: 8, currentCooldown: 0, castRange: 4)
            abilities[.wAbyssalChains] = Ability(name: "Abyssal Chains", manaCost: 120, cooldown: 12, currentCooldown: 0, castRange: 6)
            abilities[.eVoidplateResonance] = Ability(name: "Voidplate Resonance", manaCost: 0, cooldown: 0, currentCooldown: 0, castRange: 0)
            abilities[.rRuptureOfTheVoid] = Ability(name: "Rupture of the Void", manaCost: 200, cooldown: 80, currentCooldown: 0, castRange: 8)
        default:
            // Default abilities (Albedo/Jane)
            abilities[.qAvalanche] = Ability(name: "Avalanche", manaCost: 90, cooldown: 17, currentCooldown: 0, castRange: 10)
            abilities[.wToss] = Ability(name: "Toss", manaCost: 120, cooldown: 8, currentCooldown: 0, castRange: 5)
            abilities[.eTreeGrab] = Ability(name: "Tree Grab", manaCost: 0, cooldown: 0, currentCooldown: 0, castRange: 2)
            abilities[.rGrow] = Ability(name: "Grow", manaCost: 0, cooldown: 0, currentCooldown: 0, castRange: 0)
        }
    }
}
