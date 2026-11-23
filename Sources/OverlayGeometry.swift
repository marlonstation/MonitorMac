import Foundation
import CoreGraphics

enum OverlayGeometry {
    static let minimum: CGFloat = 144
    static let maximum: CGFloat = 200
    static let standard: CGFloat = 164
    static let layoutVersion = 2

    static func width(_ value: CGFloat) -> CGFloat {
        value.isFinite ? min(maximum, max(minimum, value)) : standard
    }
    static func resizedFrame(from frame: CGRect, proposedSide: CGFloat) -> CGRect {
        let side = width(proposedSide)
        return CGRect(x: frame.minX, y: frame.maxY - side, width: side, height: side)
    }

    static func height(_ width: CGFloat) -> CGFloat { width }
    static func restoredWidth(_ value: Double?, layoutVersion: Int) -> CGFloat {
        guard layoutVersion == Self.layoutVersion, let value else { return standard }
        return width(value)
    }
}

enum OverlayCorner: String, CaseIterable {
    case topLeft = "Top left"
    case topRight = "Top right"
    case bottomLeft = "Bottom left"
    case bottomRight = "Bottom right"

    func origin(in visibleFrame: CGRect, side: CGFloat, margin: CGFloat) -> CGPoint {
        let isLeft = self == .topLeft || self == .bottomLeft
        let isTop = self == .topLeft || self == .topRight
        let x = isLeft ? visibleFrame.minX + margin : visibleFrame.maxX - side - margin
        let y = isTop ? visibleFrame.maxY - side - margin : visibleFrame.minY + margin
        return CGPoint(x: min(max(x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - side)),
                       y: min(max(y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - side)))
    }
}
