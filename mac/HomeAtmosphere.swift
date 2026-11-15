import SwiftUI

/// A restrained, procedural wash for the expanded home. The camera area stays black.
struct HomeAtmosphere: View {
    @ObservedObject var model: Model
    let width: CGFloat
    private var tint: Color { Color(nsColor: model.mediaLightColor) }
    private var hasAgent: Bool { collapsedAgent(model.agentItems) != nil }
    var body: some View {
        let height: CGFloat = 178
        Canvas { context, size in
            let area = CGRect(origin: .zero, size: size)
            let base: Color = model.homeBackground == .graphite ? .white : Color(red: 0.55, green: 0.68, blue: 0.82)
            context.fill(Path(area), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: base.opacity(0.045), location: 0.35), .init(color: base.opacity(0.09), location: 1)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
            let agentTint = Color(red: 0.25, green: 0.52, blue: 0.82)
            if model.homeBackground == .dynamic || model.homeBackground == .blue {
                let strength = model.homeBackground == .blue ? 0.34 : (hasAgent ? 0.28 : 0.14)
                let center = CGPoint(x: size.width * 0.58, y: size.height * 0.65)
                context.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [agentTint.opacity(strength), agentTint.opacity(strength * 0.40), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 0.50))
            }
            if (model.homeBackground == .dynamic || model.homeBackground == .album) && model.mediaArtwork != nil {
                let strength = model.homeBackground == .album ? 0.30 : 0.20
                let center = CGPoint(x: size.width * 0.18, y: size.height * 0.54)
                context.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [tint.opacity(strength), tint.opacity(strength * 0.30), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 0.35))
            }
            // Fixed seed avoids flicker as status and playback information update.
            for i in 0..<1600 {
                let x = CGFloat((i &* 67_631 &+ 7_919) % 10_007) / 10_007 * size.width
                let y = CGFloat((i &* 2_039 &+ 571) % 8_191) / 8_191 * size.height
                let opacity = Double((i &* 17) % 7 + 1) * 0.005
                context.fill(Path(CGRect(x: x, y: y, width: 0.45, height: 0.45)), with: .color(.white.opacity(opacity)))
            }
        }
        .frame(width: width, height: height)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.65), location: 0.18), .init(color: .white, location: 0.48), .init(color: .white.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom))
        .padding(.top, 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
