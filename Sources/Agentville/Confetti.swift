import SpriteKit

enum Confetti {
    /// Throws a handful of coloured squares up from `point` and lets them fall.
    static func burst(in parent: SKNode, at point: CGPoint) {
        for _ in 0..<30 {
            let side = CGFloat.random(in: 3...5)
            let piece = SKSpriteNode(color: PixelArt.color(Int.random(in: 0..<PixelArt.palette.count)),
                                     size: CGSize(width: side, height: side))
            piece.position = point
            piece.zPosition = 500
            parent.addChild(piece)

            let velocityX = CGFloat.random(in: -90...90)
            let velocityY = CGFloat.random(in: 90...210)
            let spin = CGFloat.random(in: -8...8)
            let duration = 1.3
            let fly = SKAction.customAction(withDuration: duration) { node, elapsed in
                node.position = CGPoint(x: point.x + velocityX * elapsed,
                                        y: point.y + velocityY * elapsed - 260 * elapsed * elapsed)
                node.zRotation = spin * elapsed
                node.alpha = elapsed < 0.9 ? 1 : max(0, 1 - (elapsed - 0.9) / 0.4)
            }
            piece.run(.sequence([fly, .removeFromParent()]))
        }
    }
}
