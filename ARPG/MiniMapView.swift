import UIKit
import simd

class MiniMapView: UIView {
    private var heroPosition: SIMD2<Float>?
    private var heroRotation: Float?
    private var objectPositions: [SIMD2<Float>] = []
    private var halfSize: Float = 90.0
    private let borderColor = UIColor(white: 1.0, alpha: 0.6)
    private let backgroundColorCustom = UIColor(red: 0.05, green: 0.1, blue: 0.15, alpha: 0.95)
    private let heroColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
    private let heroArrowColor = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0)
    private let objectColor = UIColor(red: 0.6, green: 0.8, blue: 0.4, alpha: 0.8)
    private let boundaryColor = UIColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 0.9)
    private let waterColor = UIColor(red: 0.05, green: 0.13, blue: 0.22, alpha: 0.7)
    private let landColor = UIColor(red: 0.15, green: 0.25, blue: 0.1, alpha: 0.6)
    private let boundaryLineWidth: CGFloat = 2.5
    private let cornerRadius: CGFloat = 10.0
    
    // Dota 2 style properties
    private let minimapBorderWidth: CGFloat = 3.0
    private let minimapShadowRadius: CGFloat = 8.0
    private let heroMarkerSize: CGFloat = 10.0
    private let heroArrowLength: CGFloat = 6.0
    private let objectMarkerSize: CGFloat = 2.5
    
    private var boundaryPath: UIBezierPath {
        let rect = bounds.insetBy(dx: minimapBorderWidth, dy: minimapBorderWidth)
        return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = minimapShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 2)
    }
    
    func update(hero: SIMD2<Float>?, heroRotation: Float?, objects: [SIMD2<Float>], halfSize: Float) {
        self.heroPosition = hero
        self.heroRotation = heroRotation
        self.objectPositions = objects
        self.halfSize = max(halfSize, 1.0)
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Draw outer border (Dota 2 style)
        context.setFillColor(UIColor(white: 0.0, alpha: 0.3).cgColor)
        let outerPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius + 2)
        context.addPath(outerPath.cgPath)
        context.fillPath()
        
        // Draw main background
        let mapRect = boundaryPath.bounds
        context.setFillColor(backgroundColorCustom.cgColor)
        let roundedPath = UIBezierPath(roundedRect: mapRect, cornerRadius: cornerRadius)
        context.addPath(roundedPath.cgPath)
        context.fillPath()
        
        // Draw island/land area (circular with noise)
        drawIslandArea(in: context, rect: mapRect)
        
        // Draw boundary
        context.setStrokeColor(boundaryColor.cgColor)
        context.setLineWidth(boundaryLineWidth)
        context.addPath(roundedPath.cgPath)
        context.strokePath()
        
        // Draw outer border
        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(minimapBorderWidth)
        context.addPath(roundedPath.cgPath)
        context.strokePath()
        
        // Draw objects first (so hero appears on top)
        drawObjects(in: context, rect: mapRect)
        
        // Draw hero last (on top)
        drawHero(in: context, rect: mapRect)
    }
    
    private func drawIslandArea(in context: CGContext, rect: CGRect) {
        // Draw water background
        context.setFillColor(waterColor.cgColor)
        context.fillEllipse(in: rect)
        
        // Draw land/island area (circular with some variation)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.45
        
        context.setFillColor(landColor.cgColor)
        let islandPath = UIBezierPath(arcCenter: center,
                                      radius: radius,
                                      startAngle: 0,
                                      endAngle: .pi * 2,
                                      clockwise: true)
        context.addPath(islandPath.cgPath)
        context.fillPath()
        
        // Add some texture/noise to the island
        context.setBlendMode(.overlay)
        context.setFillColor(UIColor(white: 1.0, alpha: 0.1).cgColor)
        for _ in 0..<20 {
            let noiseX = center.x + CGFloat.random(in: -radius...radius) * 0.8
            let noiseY = center.y + CGFloat.random(in: -radius...radius) * 0.8
            let noiseRadius: CGFloat = 3.0
            if sqrt(pow(noiseX - center.x, 2) + pow(noiseY - center.y, 2)) < radius {
                context.fillEllipse(in: CGRect(x: noiseX - noiseRadius, y: noiseY - noiseRadius,
                                               width: noiseRadius * 2, height: noiseRadius * 2))
            }
        }
        context.setBlendMode(.normal)
    }
    
    private func point(for position: SIMD2<Float>, in rect: CGRect) -> CGPoint {
        let normalizedX = CGFloat((position.x / halfSize + 1.0) * 0.5)
        let normalizedY = CGFloat((position.y / halfSize + 1.0) * 0.5)
        let x = rect.origin.x + normalizedX * rect.width
        let y = rect.origin.y + (1.0 - normalizedY) * rect.height
        return CGPoint(x: x, y: y)
    }
    
    private func drawObjects(in context: CGContext, rect: CGRect) {
        context.setFillColor(objectColor.cgColor)
        for pos in objectPositions.prefix(150) {
            let point = self.point(for: pos, in: rect)
            // Only draw if within island area
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let distance = sqrt(pow(point.x - center.x, 2) + pow(point.y - center.y, 2))
            let maxDistance = min(rect.width, rect.height) * 0.45
            if distance < maxDistance {
                context.fillEllipse(in: CGRect(x: point.x - objectMarkerSize * 0.5,
                                              y: point.y - objectMarkerSize * 0.5,
                                              width: objectMarkerSize,
                                              height: objectMarkerSize))
            }
        }
    }
    
    private func drawHero(in context: CGContext, rect: CGRect) {
        guard let hero = heroPosition else { return }
        
        let point = self.point(for: hero, in: rect)
        
        // Draw hero marker (circle with arrow showing direction)
        context.setFillColor(heroColor.cgColor)
        let heroRect = CGRect(x: point.x - heroMarkerSize * 0.5,
                             y: point.y - heroMarkerSize * 0.5,
                             width: heroMarkerSize,
                             height: heroMarkerSize)
        context.fillEllipse(in: heroRect)
        
        // Draw white border around hero
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: heroRect)
        
        // Draw direction arrow (Dota 2 style)
        if let rotation = heroRotation {
            context.setFillColor(heroArrowColor.cgColor)
            context.setStrokeColor(heroArrowColor.cgColor)
            context.setLineWidth(1.0)
            
            // Calculate arrow direction
            let angle = CGFloat(rotation)
            let arrowTipX = point.x + cos(angle) * heroArrowLength
            let arrowTipY = point.y - sin(angle) * heroArrowLength // Negative because Y is flipped
            
            // Draw arrow as a triangle
            let arrowSize: CGFloat = 4.0
            let arrowAngle1 = angle + .pi * 0.8
            let arrowAngle2 = angle - .pi * 0.8
            
            let arrowPoint1 = CGPoint(
                x: point.x + cos(arrowAngle1) * arrowSize,
                y: point.y - sin(arrowAngle1) * arrowSize
            )
            let arrowPoint2 = CGPoint(
                x: point.x + cos(arrowAngle2) * arrowSize,
                y: point.y - sin(arrowAngle2) * arrowSize
            )
            
            let arrowPath = UIBezierPath()
            arrowPath.move(to: CGPoint(x: arrowTipX, y: arrowTipY))
            arrowPath.addLine(to: arrowPoint1)
            arrowPath.addLine(to: arrowPoint2)
            arrowPath.close()
            
            context.addPath(arrowPath.cgPath)
            context.fillPath()
            context.strokePath()
        }
        
        // Draw inner highlight
        context.setFillColor(UIColor(white: 1.0, alpha: 0.3).cgColor)
        let innerSize = heroMarkerSize * 0.4
        context.fillEllipse(in: CGRect(x: point.x - innerSize * 0.5,
                                      y: point.y - innerSize * 0.5,
                                      width: innerSize,
                                      height: innerSize))
    }
}
