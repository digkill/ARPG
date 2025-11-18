//
//  SoundManager.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import AVFoundation
import Foundation

class SoundManager {
    static let shared = SoundManager()
    
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var backgroundMusicPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // Preload sound effect
    func preloadSound(name: String, fileExtension: String = "mp3") {
        guard audioPlayers[name] == nil else {
            return // Already loaded
        }
        
        guard let url = findSoundURL(name: name, fileExtension: fileExtension) else {
            print("⚠️ Sound file not found for preload: \(name).\(fileExtension)")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[name] = player
            print("✅ Preloaded sound: \(name)")
        } catch {
            print("❌ Failed to load sound \(name): \(error)")
        }
    }
    
    // Find sound file URL - tries multiple paths
    private func findSoundURL(name: String, fileExtension: String) -> URL? {
        // Try multiple paths
        let paths: [String?] = [
            "Resources/Sounds",
            "Sounds",
            nil  // Root bundle
        ]
        
        for path in paths {
            if let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: path) {
                return url
            }
        }
        
        // Try direct file paths
        if let resourcePath = Bundle.main.resourcePath {
            let directPaths = [
                "\(resourcePath)/Resources/Sounds/\(name).\(fileExtension)",
                "\(resourcePath)/Sounds/\(name).\(fileExtension)",
                "\(resourcePath)/\(name).\(fileExtension)"
            ]
            
            for directPath in directPaths {
                if FileManager.default.fileExists(atPath: directPath) {
                    return URL(fileURLWithPath: directPath)
                }
            }
        }
        
        return nil
    }
    
    // Play sound effect
    func playSound(name: String, fileExtension: String = "mp3", volume: Float = 0.7) {
        // Try to use preloaded player
        if let player = audioPlayers[name] {
            player.volume = volume
            player.currentTime = 0
            player.play()
            return
        }
        
        // Try to load and play on the fly
        guard let url = findSoundURL(name: name, fileExtension: fileExtension) else {
            // Only print warning once per sound to avoid spam
            if !audioPlayers.keys.contains(name) {
                print("⚠️ Sound file not found: \(name).\(fileExtension) (tried multiple paths)")
            }
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            audioPlayers[name] = player
            print("✅ Playing sound: \(name)")
        } catch {
            print("❌ Failed to play sound \(name): \(error)")
        }
    }
    
    // Play background music
    func playBackgroundMusic(name: String, fileExtension: String = "mp3", volume: Float = 0.5, loop: Bool = true) {
        stopBackgroundMusic()
        
        guard let url = findSoundURL(name: name, fileExtension: fileExtension) else {
            print("⚠️ Background music file not found: \(name).\(fileExtension)")
            return
        }
        
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.numberOfLoops = loop ? -1 : 0  // -1 = infinite loop
            player.prepareToPlay()
            player.play()
            backgroundMusicPlayer = player
            print("✅ Playing background music: \(name)")
        } catch {
            print("❌ Failed to play background music \(name): \(error)")
        }
    }
    
    // Stop background music
    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
        backgroundMusicPlayer = nil
    }
    
    // Set background music volume
    func setBackgroundMusicVolume(_ volume: Float) {
        backgroundMusicPlayer?.volume = volume
    }
    
    // Stop all sounds
    func stopAllSounds() {
        for player in audioPlayers.values {
            player.stop()
        }
        stopBackgroundMusic()
    }
}

