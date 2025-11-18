//
//  SplashViewController.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//

import UIKit
import AVKit
import AVFoundation

class SplashViewController: UIViewController {
    
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoURL: URL?
    
    // Support only landscape orientation
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeLeft
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        
        // Добавляем тап для пропуска видео
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(skipVideo))
        view.addGestureRecognizer(tapGesture)
        view.isUserInteractionEnabled = true
        
        // Загружаем видео
        loadVideo()
    }
    
    @objc private func skipVideo() {
        print("⏭️ Video skipped by user")
        transitionToMenu()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Начинаем воспроизведение видео
        player?.play()
    }
    
    private func loadVideo() {
        var videoURL: URL?
        
        // Пробуем загрузить из bundle
        if let bundleURL = Bundle.main.url(forResource: "Splash_logo_video", withExtension: "mp4", subdirectory: "Resources/Video") {
            videoURL = bundleURL
            print("✅ Video found in bundle: \(bundleURL.path)")
        } else if let bundleURL = Bundle.main.url(forResource: "Splash_logo_video", withExtension: "mp4") {
            videoURL = bundleURL
            print("✅ Video found in bundle root: \(bundleURL.path)")
        } else {
            // Fallback: через resourcePath
            if let resourcePath = Bundle.main.resourcePath {
                let videoPath = (resourcePath as NSString).appendingPathComponent("Resources/Video/Splash_logo_video.mp4")
                if FileManager.default.fileExists(atPath: videoPath) {
                    videoURL = URL(fileURLWithPath: videoPath)
                    print("✅ Video found at resource path: \(videoPath)")
                }
            }
        }
        
        guard let url = videoURL else {
            print("⚠️ Video file not found, transitioning to menu")
            // Если видео не найдено, сразу переходим к меню
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.transitionToMenu()
            }
            return
        }
        
        self.videoURL = url
        
        // Создаем AVPlayer
        player = AVPlayer(url: url)
        
        // Создаем AVPlayerLayer
        playerLayer = AVPlayerLayer(player: player)
        
        // Вычисляем размеры с отступами, чтобы видео полностью помещалось
        let padding: CGFloat = 20.0
        let videoFrame = CGRect(
            x: padding,
            y: padding,
            width: view.bounds.width - (padding * 2),
            height: view.bounds.height - (padding * 2)
        )
        
        playerLayer?.frame = videoFrame
        playerLayer?.videoGravity = .resizeAspect // Изменено с resizeAspectFill на resizeAspect
        
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }
        
        // Настраиваем уведомление о завершении видео
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(videoDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem
        )
        
        // Настраиваем уведомление о готовности к воспроизведению
        player?.currentItem?.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        
        print("✅ Splash video loaded successfully")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let playerItem = player?.currentItem {
                switch playerItem.status {
                case .readyToPlay:
                    print("✅ Video is ready to play")
                case .failed:
                    print("❌ Video failed to load: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                    transitionToMenu()
                case .unknown:
                    print("⚠️ Video status unknown")
                @unknown default:
                    break
                }
            }
        }
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Обновляем размер playerLayer при изменении размера view с отступами
        let padding: CGFloat = 20.0
        let videoFrame = CGRect(
            x: padding,
            y: padding,
            width: view.bounds.width - (padding * 2),
            height: view.bounds.height - (padding * 2)
        )
        playerLayer?.frame = videoFrame
    }
    
    @objc private func videoDidFinish() {
        print("✅ Splash video finished, transitioning to menu")
        transitionToMenu()
    }
    
    private func transitionToMenu() {
        // Удаляем наблюдатели
        NotificationCenter.default.removeObserver(self)
        player?.currentItem?.removeObserver(self, forKeyPath: "status")
        
        // Останавливаем воспроизведение
        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        
        // Переход к главному меню
        let menuViewController = MenuViewController()
        
        // Плавный переход через window
        if let windowScene = view.window?.windowScene,
           let window = windowScene.windows.first {
            UIView.transition(with: window, duration: 0.5, options: .transitionCrossDissolve, animations: {
                window.rootViewController = menuViewController
            }, completion: nil)
        } else if let window = view.window {
            UIView.transition(with: window, duration: 0.5, options: .transitionCrossDissolve, animations: {
                window.rootViewController = menuViewController
            }, completion: nil)
        } else {
            // Fallback: если window не найден, используем present
            menuViewController.modalPresentationStyle = .fullScreen
            menuViewController.modalTransitionStyle = .crossDissolve
            present(menuViewController, animated: true, completion: nil)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.currentItem?.removeObserver(self, forKeyPath: "status")
    }
}

