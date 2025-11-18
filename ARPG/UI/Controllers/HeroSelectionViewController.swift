//
//  HeroSelectionViewController.swift
//  ARPG
//
//  Created by Codex on 18.11.2025.
//

import UIKit

class HeroSelectionViewController: UIViewController {
    
    var onHeroSelected: ((HeroDefinition) -> Void)?
    
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
        
        // Полупрозрачный темный фон
        view.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.9)
        
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("DEBUG: HeroSelectionViewController viewWillAppear")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("DEBUG: HeroSelectionViewController viewDidAppear, frame: \(view.frame)")
    }
    
    private func setupUI() {
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Выберите героя"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 400),
            titleLabel.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Hero selection container
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 600),
            containerView.heightAnchor.constraint(equalToConstant: 300)
        ])
        
        // Create hero buttons
        let heroes = HeroRegistry.shared.allHeroes
        guard !heroes.isEmpty else {
            let label = UILabel()
            label.text = "Герои не зарегистрированы"
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 20, weight: .regular)
            label.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
            ])
            return
        }
        let buttonWidth: CGFloat = 250
        let buttonHeight: CGFloat = 80
        let spacing: CGFloat = 40
        let totalWidth = CGFloat(heroes.count) * buttonWidth + CGFloat(max(heroes.count - 1, 0)) * spacing
        let startX = (600 - totalWidth) / 2
        
        for (index, hero) in heroes.enumerated() {
            let button = createHeroButton(hero: hero)
            button.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(button)
            
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: startX + CGFloat(index) * (buttonWidth + spacing)),
                button.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: buttonWidth),
                button.heightAnchor.constraint(equalToConstant: buttonHeight)
            ])
        }
    }
    
    private func createHeroButton(hero: HeroDefinition) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(hero.displayName, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        button.backgroundColor = UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.8)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0).cgColor
        
        // Add shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.shadowRadius = 8
        button.layer.shadowOpacity = 0.3
        
        // Highlight effect
        button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        // Selection action
        button.addAction(UIAction { [weak self] _ in
            SoundManager.shared.playSound(name: "button_click", fileExtension: "mp3", volume: 0.8)
            self?.onHeroSelected?(hero)
        }, for: .touchUpInside)
        
        return button
    }
    
    @objc private func buttonTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            sender.backgroundColor = UIColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.9)
        }
    }
    
    @objc private func buttonTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
            sender.backgroundColor = UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 0.8)
        }
    }
}
