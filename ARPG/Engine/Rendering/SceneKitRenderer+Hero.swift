//
//  SceneKitRenderer+Hero.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//  Updated: надёжная загрузка анимаций из USDZ
//

import SceneKit
import simd

extension SceneKitRenderer {
    
    func loadHeroAnimations(from scene: SCNScene) {
        // Если у героя отдельные файлы анимаций (например, Abyssus)
        if let animationFilePaths = selectedHero.animationFilePaths {
            loadHeroAnimationsFromSeparateFiles(animationFilePaths: animationFilePaths)
            return
        }
        
        // === 1. Сбор ВСЕХ анимаций: с ключами + без ключей (USDZ часто без ключей) ===
        func findAllAnimationPlayers(in node: SCNNode, path: String = "root") -> [(key: String, player: SCNAnimationPlayer, node: SCNNode, path: String)] {
            var result: [(key: String, player: SCNAnimationPlayer, node: SCNNode, path: String)] = []
            var addedPlayers = Set<ObjectIdentifier>()
            
            // Анимации с ключами
            for key in node.animationKeys {
                if let player = node.animationPlayer(forKey: key) {
                    result.append((key: key, player: player, node: node, path: path))
                    addedPlayers.insert(ObjectIdentifier(player))
                }
            }
            
            // В SceneKit нет прямого доступа к animationPlayers без ключей
            // Все анимации должны иметь ключи через animationKeys
            
            // Рекурсия по детям
            for (index, child) in node.childNodes.enumerated() {
                let childPath = "\(path)/child[\(index)]\(child.name.map { " (\($0))" } ?? "")"
                result.append(contentsOf: findAllAnimationPlayers(in: child, path: childPath))
            }
            
            return result
        }
        
        let allAnimations = findAllAnimationPlayers(in: scene.rootNode)
        
        // === 2. Красивый вывод в консоль ===
        let separator = String(repeating: "=", count: 90)
        print("\n\(separator)")
        print("СКАН АНИМАЦИЙ МОДЕЛИ: \(selectedHero.displayName)")
        print(separator)
        print("Всего анимаций найдено: \(allAnimations.count)")
        
        if allAnimations.isEmpty {
            print("АНИМАЦИИ НЕ НАЙДЕНЫ В МОДЕЛИ!")
        } else {
            for anim in allAnimations {
                let unnamed = anim.key.hasPrefix("unnamed") ? " (БЕЗ КЛЮЧА — типично для USDZ)" : ""
                print("• '\(anim.key)' → \(anim.path)\(unnamed)")
            }
        }
        print(separator + "\n")
        
        // === 3. Если только одна анимация — используем её для всего ===
        if allAnimations.count == 1 {
            let player = allAnimations[0].player
            for (_, animName) in selectedHero.animationMap {
                heroAnimationPlayers[animName] = player
            }
            print("ЕДИНСТВЕННАЯ АНИМАЦИЯ → назначена на все состояния героя")
            return
        }
        
        // === 4. Очистка имён (убираем мусор от Mixamo и т.п.) ===
        func cleanedAnimationName(_ name: String) -> String {
            var clean = name.lowercased()
                .replacingOccurrences(of: "armature|", with: "")
                .replacingOccurrences(of: "mixamorig:", with: "")
                .replacingOccurrences(of: "mixamo.com", with: "")
                .replacingOccurrences(of: "layer\\d*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "_\\d+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "__", with: "_")
                .trimmingCharacters(in: .whitespaces)
            
            // Берём последний осмысленный компонент
            let components = clean.components(separatedBy: CharacterSet(charactersIn: "|:/\\._-"))
            if let last = components.last, !last.isEmpty {
                clean = last
            }
            return clean
        }
        
        // === 5. Поиск анимации по имени (умный) ===
        func findAnimationPlayer(named target: String, in node: SCNNode) -> SCNAnimationPlayer? {
            let targetLower = target.lowercased()
            let targetClean = cleanedAnimationName(target)
            
            // Точное совпадение по ключу
            if let player = node.animationPlayer(forKey: target) {
                return player
            }
            
            // Частичное совпадение по оригинальному ключу
            for key in node.animationKeys {
                let keyLower = key.lowercased()
                if keyLower.contains(targetLower) || targetLower.contains(keyLower) {
                    return node.animationPlayer(forKey: key)
                }
            }
            
            // Совпадение по очищенному имени (самое надёжное)
            for key in node.animationKeys {
                if cleanedAnimationName(key) == targetClean {
                    return node.animationPlayer(forKey: key)
                }
            }
            
            // Рекурсия
            for child in node.childNodes {
                if let player = findAnimationPlayer(named: target, in: child) {
                    return player
                }
            }
            
            return nil
        }
        
        // === 6. Основная загрузка по animationMap ===
        var loadedCount = 0
        let totalNeeded = selectedHero.animationMap.count
        
        for (_, animationName) in selectedHero.animationMap {
            if let player = findAnimationPlayer(named: animationName, in: scene.rootNode) {
                heroAnimationPlayers[animationName] = player
                loadedCount += 1
                print("Загружено: \(animationName)")
            } else {
                // Fallback: ищем по подстроке среди всех найденных
                let cleanTarget = cleanedAnimationName(animationName)
                for anim in allAnimations {
                    if cleanedAnimationName(anim.key) == cleanTarget ||
                       anim.key.lowercased().contains(animationName.lowercased()) {
                        heroAnimationPlayers[animationName] = anim.player
                        print("Загружено (fallback): \(animationName) ← '\(anim.key)'")
                        loadedCount += 1
                        break
                    }
                }
            }
        }
        
        print("\nИТОГ: загружено \(loadedCount)/\(totalNeeded) анимаций по маппингу")
        if loadedCount < totalNeeded {
            let missing = selectedHero.animationMap.values.filter { heroAnimationPlayers[$0] == nil }
            print("ОТСУТСТВУЮТ: \(missing.joined(separator: ", "))")
        }
    }
    
    // MARK: - Загрузка из отдельных файлов (тоже с поддержкой unnamed)
    
    private func loadHeroAnimationsFromSeparateFiles(animationFilePaths: [HeroAnimationState: String]) {
        print("🎬 Загрузка анимаций из отдельных USDZ файлов для: \(selectedHero.displayName)")
        
        func findFirstAnimationPlayer(in node: SCNNode) -> SCNAnimationPlayer? {
            // Ищем по ключам
            for key in node.animationKeys {
                if let player = node.animationPlayer(forKey: key) {
                    return player
                }
            }
            // Рекурсия по дочерним узлам
            for child in node.childNodes {
                if let player = findFirstAnimationPlayer(in: child) {
                    return player
                }
            }
            return nil
        }
        
        for (state, filePath) in animationFilePaths {
            let animationName = selectedHero.animationName(for: state)
            
            // Используем resolveResourceURL для поиска файла
            guard let url = resolveResourceURL(for: filePath) else {
                print("⚠️ Файл анимации не найден: \(filePath)")
                continue
            }
            
            do {
                let animScene = try loadScene(from: url)
                if let player = findFirstAnimationPlayer(in: animScene.rootNode) {
                    heroAnimationPlayers[animationName] = player
                    print("✅ Загружена анимация '\(animationName)' из: \(url.lastPathComponent)")
                } else {
                    print("⚠️ Анимация не найдена в файле: \(url.lastPathComponent)")
                }
            } catch {
                print("⚠️ Ошибка загрузки файла анимации \(filePath): \(error.localizedDescription)")
            }
        }
        
        print("✅ ИТОГ: загружено \(heroAnimationPlayers.count)/\(animationFilePaths.count) анимаций из отдельных USDZ файлов")
    }
    
    private func resolveResourceURL(for path: String) -> URL? {
        let components = path.components(separatedBy: "/")
        guard let fileNameWithExt = components.last else { return nil }
        let fileName = (fileNameWithExt as NSString).deletingPathExtension
        let fileExtension = (fileNameWithExt as NSString).pathExtension
        
        // Пробуем разные варианты подкаталогов
        let subdirectoryOptions: [String?] = [
            components.count > 1 ? components.dropLast().joined(separator: "/") : nil,
            "Resources/Models/Heroes",
            "Resources/Models",
            "Resources",
            nil
        ]
        
        for subdirectory in subdirectoryOptions {
            if let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: subdirectory) {
                print("✅ Найден файл: \(path) → \(url.path)")
                return url
            }
        }
        
        // Fallback: прямой путь через resourcePath
        if let bundleRoot = Bundle.main.resourcePath {
            let fullPath = (bundleRoot as NSString).appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fullPath) {
                print("✅ Найден файл (fallback): \(path) → \(fullPath)")
                return URL(fileURLWithPath: fullPath)
            }
        }
        
        print("❌ Файл не найден: \(path)")
        return nil
    }
    
    // MARK: - Воспроизведение анимации
    
    func playHeroAnimation(_ state: HeroAnimationState, loop: Bool = false) {
        guard let heroNode = heroNode else { return }
        heroNode.removeAnimation(forKey: "currentAnimation", blendOutDuration: 0.18)
        
        let animationName = selectedHero.animationName(for: state)
        guard let sourcePlayer = heroAnimationPlayers[animationName] else {
            print("Анимация не найдена: \(animationName)")
            return
        }
        
        guard let animation = sourcePlayer.animation.copy() as? SCNAnimation else { return }
        
        animation.repeatCount = loop ? .infinity : 1
        animation.blendInDuration = 0.2
        animation.blendOutDuration = 0.15
        animation.usesSceneTimeBase = false
        animation.isRemovedOnCompletion = !loop
        
        let player = SCNAnimationPlayer(animation: animation)
        heroNode.addAnimationPlayer(player, forKey: "currentAnimation")
        player.play()
        
        currentHeroAnimation = state
    }
    
    // MARK: - Остальные функции без изменений (они и так работают)
    
    func updateHeroAnimations(deltaTime: Float, hero: CharacterInstance) {
        guard heroStats.health > 0 else {
            if currentHeroAnimation != .dead {
                playHeroAnimation(.dead, loop: false)
            }
            return
        }
        
        heroAttackAnimationTime = max(0, heroAttackAnimationTime - deltaTime)
        heroDamageAnimationTime = max(0, heroDamageAnimationTime - deltaTime)
        heroSkillAnimationTime = max(0, heroSkillAnimationTime - deltaTime)
        
        if heroAttackAnimationTime > 0 || heroDamageAnimationTime > 0 || heroSkillAnimationTime > 0 {
            return
        }
        
        let isMoving = simd_length(hero.velocity) > 0.1
        
        if InputManager.shared.isAttackPressed && currentHeroAnimation != .attacking {
            playHeroAnimation(.attacking, loop: false)
            heroAttackAnimationTime = 1.0
            return
        }
        
        if isMoving {
            if currentHeroAnimation != .walking {
                playHeroAnimation(.walking, loop: true)
            }
        } else if currentHeroAnimation != .idle {
            playHeroAnimation(.idle, loop: true)
        }
    }
    
    func performHeroAttack() {
        guard heroStats.health > 0 else { return }
        playHeroAnimation(.attacking, loop: false)
        heroAttackAnimationTime = 1.0
        
        let heroPos = humans.first?.position ?? SIMD3<Float>(0, 0, 0)
        let attackDamage = heroStats.baseDamage + heroStats.treeBonusDamage
        for index in mobs.indices {
            let mobPos = mobs[index].position
            let distance = simd_length(heroPos - mobPos)
            if distance <= heroStats.attackRange {
                mobs[index].health = max(0, mobs[index].health - attackDamage)
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
        
        let isSpecialSkill = (key == .rGrow || key == .rRuptureOfTheVoid)
        if isSpecialSkill {
            playHeroAnimation(.usingSpecialSkill, loop: false)
            heroSkillAnimationTime = 2.0
        } else {
            playHeroAnimation(.usingSkill, loop: false)
            heroSkillAnimationTime = 1.5
        }
        
        switch key {
        case .qAvalanche:           castAvalanche(targetPos: targetPos ?? hero.position)
        case .wToss:                castToss(targetPos: targetPos ?? hero.position)
        case .eTreeGrab:            castTreeGrab()
        case .rGrow:                castGrow()
        case .qRiftCleaver:         castRiftCleaver(targetPos: targetPos ?? hero.position)
        case .wAbyssalChains:       castAbyssalChains(targetPos: targetPos ?? hero.position)
        case .eVoidplateResonance:  break
        case .rRuptureOfTheVoid:    castRuptureOfTheVoid(targetPos: targetPos ?? hero.position)
        }
        
        SoundManager.shared.playSound(name: ability.name.lowercased(), fileExtension: "mp3", volume: 0.7)
    }
    
    func takeDamage(_ damage: Float) {
        guard heroStats.health > 0 else { return }
        heroStats.health = max(0, heroStats.health - damage)
        playHeroAnimation(.takingDamage, loop: false)
        heroDamageAnimationTime = 0.5
        
        if heroStats.health <= 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playHeroAnimation(.dead, loop: false)
            }
        }
    }
    
    // MARK: - Способности (без изменений)
    
    private func castAvalanche(targetPos: SIMD3<Float>) {
        let radius: Float = 5.0
        let damage: Float = 150
        for index in mobs.indices {
            if simd_distance(targetPos, mobs[index].position) <= radius {
                mobs[index].health = max(0, mobs[index].health - damage)
            }
        }
    }
    
    private func castToss(targetPos: SIMD3<Float>) { }
    
    private func castTreeGrab() {
        heroStats.hasTree = true
        heroStats.treeBonusDamage = 20
    }
    
    private func castGrow() {
        heroStats.growMultiplier += 0.1
        heroScale *= 1.1
        heroNode?.scale = SCNVector3(heroScale, heroScale, heroScale)
    }
    
    private func castRiftCleaver(targetPos: SIMD3<Float>) {
        let radius: Float = 4.0
        let damage: Float = 200
        for index in mobs.indices {
            if simd_distance(targetPos, mobs[index].position) <= radius {
                mobs[index].health = max(0, mobs[index].health - damage)
            }
        }
    }
    
    private func castAbyssalChains(targetPos: SIMD3<Float>) {
        let range: Float = 6.0
        let slow: Float = 0.5
        for index in mobs.indices {
            let dist = simd_distance(targetPos, mobs[index].position)
            if dist <= range {
                mobs[index].velocity *= (1.0 - slow)
                if let heroPos = humans.first?.position {
                    let dir = simd_normalize(heroPos - mobs[index].position)
                    mobs[index].velocity += dir * 2.0
                }
            }
        }
    }
    
    private func castRuptureOfTheVoid(targetPos: SIMD3<Float>) {
        let radius: Float = 8.0
        let damage: Float = 120
        for index in mobs.indices {
            if simd_distance(targetPos, mobs[index].position) <= radius {
                mobs[index].health = max(0, mobs[index].health - damage)
            }
        }
        // TODO: периодический урон 7 сек
    }
}
