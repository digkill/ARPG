//
//  GameViewController.swift
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

import UIKit
import SceneKit
import simd

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: SceneKitRenderer!
    var sceneView: SCNView!
    
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
    var gestureOverlay: UIView!
    var fpsLabel: UILabel!
    var fpsUpdateTimer: Timer?
    var minimapView: MiniMapView!
    
    // Virtual controls
    var moveJoystick: VirtualJoystick!
    var attackButton: ActionButton!
    var jumpButton: ActionButton!
    var actionButton: ActionButton!
    var skill1Button: ActionButton!
    var skill2Button: ActionButton!
    var skill3Button: ActionButton!
    var skill4Button: ActionButton!  // Ult

    override func loadView() {
        // Create SCNView programmatically
        let sceneView = SCNView()
        sceneView.backgroundColor = .black
        self.view = sceneView
    }
    
    var selectedHero: HeroDefinition = HeroRegistry.shared.defaultHero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("DEBUG: viewDidLoad called")
        print("DEBUG: view type: \(type(of: view))")
        print("DEBUG: view frame: \(view.frame)")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("DEBUG: viewDidAppear called")
        
        // Показываем окно выбора героя после того, как view появился
        if renderer == nil {
            showHeroSelection()
        } else {
            // Если игра уже запущена, обновляем UI
            if let sceneView = self.sceneView {
                print("DEBUG: SCNView is visible, frame: \(sceneView.frame)")
                print("DEBUG: SCNView scene: \(sceneView.scene != nil ? "set" : "nil")")
            }
            
            // Update overlay frame and bring to front
            if let overlay = gestureOverlay {
                overlay.frame = view.bounds
                view.bringSubviewToFront(overlay)
                // Bring exit button to front too
                if let exitButton = view.subviews.first(where: { $0.tag == 999 }) {
                    view.bringSubviewToFront(exitButton)
                }
                // Bring FPS label to front
                if let fpsLabel = fpsLabel {
                    view.bringSubviewToFront(fpsLabel)
                }
                print("DEBUG: Gesture overlay frame updated: \(overlay.frame)")
            }
        }
    }
    
    private func showHeroSelection() {
        let heroSelectionVC = HeroSelectionViewController()
        heroSelectionVC.modalPresentationStyle = .overFullScreen
        heroSelectionVC.onHeroSelected = { [weak self] hero in
            guard let self = self else { return }
            self.selectedHero = hero
            heroSelectionVC.dismiss(animated: true) {
                self.startGame()
            }
        }
        present(heroSelectionVC, animated: true)
    }
    
    private func startGame() {
        // Start game background music
        SoundManager.shared.playBackgroundMusic(name: "game_music", fileExtension: "mp3", volume: 0.4, loop: true)

        guard let sceneView = view as? SCNView else {
            print("ERROR: View of GameViewController is not an SCNView. View type: \(type(of: view))")
            return
        }
        
        self.sceneView = sceneView
        print("DEBUG: SCNView cast successful")
        
        // Создаем SceneKit рендерер с выбранным героем
        renderer = SceneKitRenderer(sceneView: sceneView, hero: selectedHero)
        print("DEBUG: SceneKitRenderer created successfully with hero: \(selectedHero.displayName)")
        
        // Add exit button FIRST so it can receive touches
        setupExitButton()
        
        // Add FPS label
        setupFPSLabel()
        
        // Add virtual controls
        setupVirtualControls()
        
        // Create transparent overlay for gesture handling
        gestureOverlay = UIView(frame: view.bounds)
        gestureOverlay.backgroundColor = .clear
        gestureOverlay.isUserInteractionEnabled = true
        gestureOverlay.isMultipleTouchEnabled = true
        view.addSubview(gestureOverlay)
        print("DEBUG: Gesture overlay created")
        
        // Ensure exit button is always on top of overlay
        if let exitButton = view.subviews.first(where: { $0.tag == 999 }) {
            view.insertSubview(exitButton, aboveSubview: gestureOverlay)
        }
        
        // Add gesture recognizers for camera control (after renderer is set)
        setupGestures()
    }
    
    func setupExitButton() {
        let exitButton = UIButton(type: .system)
        exitButton.setTitle("В меню", for: .normal)
        exitButton.setTitleColor(.white, for: .normal)
        exitButton.backgroundColor = UIColor(white: 0.0, alpha: 0.7)
        exitButton.layer.cornerRadius = 8
        exitButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        exitButton.frame = CGRect(x: view.bounds.width - 90, y: 50, width: 80, height: 40)
        exitButton.addTarget(self, action: #selector(exitApp), for: .touchUpInside)
        exitButton.tag = 999
        exitButton.isUserInteractionEnabled = true
        view.addSubview(exitButton)
        // Add button AFTER overlay so it's on top
        if let overlay = gestureOverlay {
            view.insertSubview(exitButton, aboveSubview: overlay)
        } else {
            view.bringSubviewToFront(exitButton)
        }
        print("DEBUG: Exit button created at: \(exitButton.frame), isUserInteractionEnabled: \(exitButton.isUserInteractionEnabled)")
    }
    
    @objc func exitApp() {
        print("DEBUG: Exit button pressed - returning to menu")
        
        // Play button click sound
        SoundManager.shared.playSound(name: "button_click", fileExtension: "mp3", volume: 0.8)
        
        // Stop FPS timer
        fpsUpdateTimer?.invalidate()
        fpsUpdateTimer = nil
        
        // Stop game music
        SoundManager.shared.stopBackgroundMusic()
        
        // Dismiss and return to menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.dismiss(animated: true, completion: nil)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Stop game music when leaving
        SoundManager.shared.stopBackgroundMusic()
    }
    
    func setupVirtualControls() {
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        // Movement joystick - bottom left
        moveJoystick = VirtualJoystick(frame: CGRect(x: 20, y: screenHeight - 140, width: 120, height: 120))
        moveJoystick.onDirectionChanged = { direction in
            InputManager.shared.updateMoveDirection(direction)
        }
        moveJoystick.onReleased = {
            InputManager.shared.resetMoveDirection()
        }
        view.addSubview(moveJoystick)
        
        // Minimap next to joystick
        let minimapSize: CGFloat = 120
        let minimapX = moveJoystick.frame.maxX + 20
        let minimapY = screenHeight - minimapSize - 20
        minimapView = MiniMapView(frame: CGRect(x: minimapX, y: minimapY, width: minimapSize, height: minimapSize))
        view.addSubview(minimapView)
        
        // Attack button - bottom right
        attackButton = ActionButton(frame: CGRect(x: screenWidth - 70, y: screenHeight - 140, width: 50, height: 50))
        attackButton.setTitle("⚔", for: .normal)
        attackButton.onPressed = {
            InputManager.shared.isAttackPressed = true
            SoundManager.shared.playSound(name: "attack", fileExtension: "mp3", volume: 0.6)
        }
        attackButton.onReleased = {
            InputManager.shared.isAttackPressed = false
        }
        view.addSubview(attackButton)
        
        // Jump button - above attack
        jumpButton = ActionButton(frame: CGRect(x: screenWidth - 70, y: screenHeight - 200, width: 50, height: 50))
        jumpButton.setTitle("↑", for: .normal)
        jumpButton.onPressed = {
            InputManager.shared.isJumpPressed = true
            SoundManager.shared.playSound(name: "jump", fileExtension: "mp3", volume: 0.5)
        }
        jumpButton.onReleased = {
            InputManager.shared.isJumpPressed = false
        }
        view.addSubview(jumpButton)
        
        // Action button - left of attack
        actionButton = ActionButton(frame: CGRect(x: screenWidth - 130, y: screenHeight - 140, width: 50, height: 50))
        actionButton.setTitle("E", for: .normal)
        actionButton.onPressed = {
            InputManager.shared.isActionPressed = true
            SoundManager.shared.playSound(name: "action", fileExtension: "mp3", volume: 0.5)
        }
        actionButton.onReleased = {
            InputManager.shared.isActionPressed = false
        }
        view.addSubview(actionButton)
        
        // Skill buttons - bottom center, horizontal layout
        let skillY = screenHeight - 80.0
        let skillSpacing: CGFloat = 60
        let skillStartX = screenWidth / 2 - (skillSpacing * 1.5)  // Center horizontally
        
        skill1Button = ActionButton(frame: CGRect(x: skillStartX, y: skillY, width: 50, height: 50))
        skill1Button.setTitle("1", for: .normal)
        skill1Button.onPressed = {
            InputManager.shared.isSkill1Pressed = true
            SoundManager.shared.playSound(name: "skill", fileExtension: "mp3", volume: 0.6)
        }
        skill1Button.onReleased = {
            InputManager.shared.isSkill1Pressed = false
        }
        view.addSubview(skill1Button)
        
        skill2Button = ActionButton(frame: CGRect(x: skillStartX + skillSpacing, y: skillY, width: 50, height: 50))
        skill2Button.setTitle("2", for: .normal)
        skill2Button.onPressed = {
            InputManager.shared.isSkill2Pressed = true
            SoundManager.shared.playSound(name: "skill", fileExtension: "mp3", volume: 0.6)
        }
        skill2Button.onReleased = {
            InputManager.shared.isSkill2Pressed = false
        }
        view.addSubview(skill2Button)
        
        skill3Button = ActionButton(frame: CGRect(x: skillStartX + skillSpacing * 2, y: skillY, width: 50, height: 50))
        skill3Button.setTitle("3", for: .normal)
        skill3Button.onPressed = {
            InputManager.shared.isSkill3Pressed = true
            SoundManager.shared.playSound(name: "skill", fileExtension: "mp3", volume: 0.6)
        }
        skill3Button.onReleased = {
            InputManager.shared.isSkill3Pressed = false
        }
        view.addSubview(skill3Button)
        
        skill4Button = ActionButton(frame: CGRect(x: skillStartX + skillSpacing * 3, y: skillY, width: 50, height: 50))
        skill4Button.setTitle("ULT", for: .normal)
        skill4Button.titleLabel?.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        skill4Button.backgroundColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.3)  // Red tint for ult
        skill4Button.onPressed = {
            InputManager.shared.isSkill4Pressed = true
            SoundManager.shared.playSound(name: "ult", fileExtension: "mp3", volume: 0.8)
        }
        skill4Button.onReleased = {
            InputManager.shared.isSkill4Pressed = false
        }
        view.addSubview(skill4Button)
        
        print("✅ Virtual controls setup complete")
    }
    
    func setupFPSLabel() {
        fpsLabel = UILabel()
        fpsLabel.text = "FPS: 0"
        fpsLabel.textColor = .white
        fpsLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.7)
        fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        fpsLabel.textAlignment = .center
        fpsLabel.layer.cornerRadius = 6
        fpsLabel.clipsToBounds = true
        fpsLabel.frame = CGRect(x: 10, y: 50, width: 80, height: 30)
        fpsLabel.isUserInteractionEnabled = false
        view.addSubview(fpsLabel)
        
        // Update FPS every 0.1 seconds
        fpsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let renderer = self.renderer else { return }
                self.fpsLabel.text = "FPS: \(renderer.getFPS())"
                let minimapData = renderer.getMinimapData()
                self.minimapView?.update(hero: minimapData.hero,
                                         heroRotation: minimapData.heroRotation,
                                         objects: minimapData.objects,
                                         halfSize: minimapData.halfSize)
            }
        }
        
        print("DEBUG: FPS label created at: \(fpsLabel.frame)")
    }
    
    func setupGestures() {
        print("DEBUG: Setting up gesture recognizers")
        
        // Dota 2 style - no camera controls via gestures
        // Camera automatically follows hero with fixed angle
        print("DEBUG: Camera gestures disabled (Dota 2 style)")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("DEBUG: viewWillAppear called")
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update overlay frame when view layout changes
        if let overlay = gestureOverlay {
            overlay.frame = view.bounds
            view.bringSubviewToFront(overlay)
        }
        // Update exit button position
        if let exitButton = view.subviews.first(where: { $0.tag == 999 }) {
            exitButton.frame = CGRect(x: view.bounds.width - 90, y: 50, width: 80, height: 40)
            view.bringSubviewToFront(exitButton)
        }
        // Update FPS label position
        if let fpsLabel = fpsLabel {
            fpsLabel.frame = CGRect(x: 10, y: 50, width: 80, height: 30)
            view.bringSubviewToFront(fpsLabel)
        }
        
        // Update virtual controls positions
        let screenWidth = view.bounds.width
        let screenHeight = view.bounds.height
        
        if let moveJoystick = moveJoystick {
            moveJoystick.frame = CGRect(x: 20, y: screenHeight - 140, width: 120, height: 120)
            view.bringSubviewToFront(moveJoystick)
        }
        
        // Update minimap position
        if let minimapView = minimapView {
            let minimapSize: CGFloat = 120
            let minimapX = (moveJoystick?.frame.maxX ?? 20) + 20
            let minimapY = screenHeight - minimapSize - 20
            minimapView.frame = CGRect(x: minimapX, y: minimapY, width: minimapSize, height: minimapSize)
            view.bringSubviewToFront(minimapView)
        }
        
        if let attackButton = attackButton {
            attackButton.frame = CGRect(x: screenWidth - 70, y: screenHeight - 140, width: 50, height: 50)
            view.bringSubviewToFront(attackButton)
        }
        
        if let jumpButton = jumpButton {
            jumpButton.frame = CGRect(x: screenWidth - 70, y: screenHeight - 200, width: 50, height: 50)
            view.bringSubviewToFront(jumpButton)
        }
        
        if let actionButton = actionButton {
            actionButton.frame = CGRect(x: screenWidth - 130, y: screenHeight - 140, width: 50, height: 50)
            view.bringSubviewToFront(actionButton)
        }
        
        // Skill buttons - bottom center, horizontal layout
        let skillY = screenHeight - 80.0
        let skillSpacing: CGFloat = 60
        let skillStartX = screenWidth / 2 - (skillSpacing * 1.5)  // Center horizontally
        
        if let skill1Button = skill1Button {
            skill1Button.frame = CGRect(x: skillStartX, y: skillY, width: 50, height: 50)
            view.bringSubviewToFront(skill1Button)
        }
        
        if let skill2Button = skill2Button {
            skill2Button.frame = CGRect(x: skillStartX + skillSpacing, y: skillY, width: 50, height: 50)
            view.bringSubviewToFront(skill2Button)
        }
        
        if let skill3Button = skill3Button {
            skill3Button.frame = CGRect(x: skillStartX + skillSpacing * 2, y: skillY, width: 50, height: 50)
            view.bringSubviewToFront(skill3Button)
        }
        
        if let skill4Button = skill4Button {
            skill4Button.frame = CGRect(x: skillStartX + skillSpacing * 3, y: skillY, width: 50, height: 50)
            view.bringSubviewToFront(skill4Button)
        }
    }
    
    // Direct touch handling removed - camera movement via swipes is disabled
    // Only zoom via pinch gesture is available
}
