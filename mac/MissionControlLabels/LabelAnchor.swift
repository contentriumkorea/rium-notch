import Foundation
import CoreGraphics

public enum LabelAnchor: String, CaseIterable, Sendable {
    case center, topLeft, topCenter, topRight, middleLeft, middleRight, bottomLeft, bottomCenter, bottomRight

    public static let `default`: LabelAnchor = .center

    public var displayName: String {
        switch self {
        case .center: return "Center"
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }

    /// Localizable.strings에서 메뉴 제목을 찾는 키
    public var localizationKey: String { "anchor.\(rawValue)" }

    public enum TextAlignment: Sendable { case left, center, right }

    public var textAlignment: TextAlignment {
        switch self {
        case .center, .topCenter, .bottomCenter: return .center
        case .topLeft, .middleLeft, .bottomLeft: return .left
        case .topRight, .middleRight, .bottomRight: return .right
        }
    }

    /// AppKit 좌표(y 위로 증가)의 썸네일 사각형 안에 크기 `size`의 라벨을 놓을 원점
    public func origin(labelSize size: CGSize, in thumb: CGRect, inset: CGFloat) -> CGPoint {
        let x: CGFloat, y: CGFloat
        switch self {
        case .center, .topCenter, .bottomCenter:
            x = thumb.midX - size.width / 2
        case .topLeft, .middleLeft, .bottomLeft:
            x = thumb.minX + inset
        case .topRight, .middleRight, .bottomRight:
            x = thumb.maxX - inset - size.width
        }
        switch self {
        case .topLeft, .topCenter, .topRight:
            y = thumb.maxY - inset - size.height
        case .middleLeft, .center, .middleRight:
            y = thumb.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = thumb.minY + inset
        }
        return CGPoint(x: round(x), y: round(y))
    }
}
