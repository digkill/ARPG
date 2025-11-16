//
//  MenuViewController.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import UIKit

class MenuViewController: UIViewController {
    
    var logoImageView: UIImageView!
    var startButton: UIButton!
    var exitButton: UIButton!
    
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
        
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)  // Dark blue background
        
        setupLogo()
        setupButtons()
        
        // Start background music
        SoundManager.shared.playBackgroundMusic(name: "menu_music", fileExtension: "mp3", volume: 0.3, loop: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop background music when leaving menu
        SoundManager.shared.stopBackgroundMusic()
    }
    
    func setupLogo() {
        // Try multiple ways to load logo image
        var logoImage: UIImage? = nil
        
        // Method 1: From Resources/Images folder
        if let logoPath = Bundle.main.path(forResource: "logo-mr", ofType: "png", inDirectory: "Resources/Images") {
            logoImage = UIImage(contentsOfFile: logoPath)
            print("DEBUG: Trying logo from Resources/Images: \(logoPath)")
        }
        
        // Method 2: Direct from bundle root
        if logoImage == nil, let imagePath = Bundle.main.path(forResource: "logo-mr", ofType: "png") {
            logoImage = UIImage(contentsOfFile: imagePath)
            print("DEBUG: Trying logo from bundle root: \(imagePath)")
        }
        
        // Method 3: From Assets
        if logoImage == nil {
            logoImage = UIImage(named: "logo-mr")
            print("DEBUG: Trying logo from Assets")
        }
        
        if let logoImage = logoImage {
            logoImageView = UIImageView(image: logoImage)
            logoImageView.contentMode = .scaleAspectFit
            logoImageView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(logoImageView)
            
            NSLayoutConstraint.activate([
                logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                logoImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
                logoImageView.widthAnchor.constraint(equalToConstant: 300),
                logoImageView.heightAnchor.constraint(equalToConstant: 300)
            ])
            
            print("✅ Logo loaded successfully")
        } else {
            // Fallback: create a text label if logo not found
            let logoLabel = UILabel()
            logoLabel.text = "ARPG"
            logoLabel.textColor = .white
            logoLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
            logoLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(logoLabel)
            
            NSLayoutConstraint.activate([
                logoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                logoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100)
            ])
            
            print("⚠️ Logo image not found, using text label")
        }
    }
    
    func setupButtons() {
        // Start button
        startButton = UIButton(type: .system)
        startButton.setTitle("Начать игру", for: .normal)
        startButton.setTitleColor(.white, for: .normal)
        startButton.backgroundColor = UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1.0)  // Green
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        startButton.layer.cornerRadius = 12
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startGame), for: .touchUpInside)
        view.addSubview(startButton)
        
        // Exit button
        exitButton = UIButton(type: .system)
        exitButton.setTitle("Выход", for: .normal)
        exitButton.setTitleColor(.white, for: .normal)
        exitButton.backgroundColor = UIColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1.0)  // Red
        exitButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        exitButton.layer.cornerRadius = 10
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        exitButton.addTarget(self, action: #selector(exitApp), for: .touchUpInside)
        view.addSubview(exitButton)
        
        NSLayoutConstraint.activate([
            // Start button
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 50),
            startButton.widthAnchor.constraint(equalToConstant: 200),
            startButton.heightAnchor.constraint(equalToConstant: 60),
            
            // Exit button
            exitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exitButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 30),
            exitButton.widthAnchor.constraint(equalToConstant: 150),
            exitButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc func startGame() {
        print("DEBUG: Start game button pressed")
        
        // Play button click sound
        SoundManager.shared.playSound(name: "button_click", fileExtension: "mp3", volume: 0.8)
        
        // Animate button press
        UIView.animate(withDuration: 0.1, animations: {
            self.startButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.startButton.transform = .identity
            }
        }
        
        // Small delay before transition to allow sound to play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Transition to game - create GameViewController programmatically
            let gameViewController = GameViewController()
            gameViewController.modalPresentationStyle = .fullScreen
            gameViewController.modalTransitionStyle = .crossDissolve
            self.present(gameViewController, animated: true, completion: nil)
        }
    }
    
    @objc func exitApp() {
        print("DEBUG: Exit button pressed from menu")
        
        // Play button click sound
        SoundManager.shared.playSound(name: "button_click", fileExtension: "mp3", volume: 0.8)
        
        // Small delay before exit to allow sound to play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}

