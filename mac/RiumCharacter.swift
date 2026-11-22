import SwiftUI

func riumEyeRect(side: CGFloat, gazeX: CGFloat, gazeY: CGFloat, openness: CGFloat, scale: CGFloat) -> CGRect {
    let width = 16 * min(1.15, scale)
    let height = 35 * min(1, openness) * scale
    let x = 50 + side * 13.2 + gazeX * 4.5
    let y = 49 + gazeY * 3
    return CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
}

// One character is shared by all AI sessions; its expression reflects their state.
struct RiumCharacter: View {
    let motion: [Double]
    let headAngle: Double
    let face: Int32
    let eyeScale: Double
    let lamp: Double
    let scaleX: Double
    let scaleY: Double

    var body: some View {
        Canvas { context, size in
            guard motion.count >= 3 else { return }
            let side = min(size.width, size.height)
            guard side > 0 else { return }
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 100, y: side / 100)
            context.translateBy(x: 50, y: 50)
            let rotation = headAngle + (motion.count > 3 ? motion[3] : 0)
            context.rotate(by: .degrees(rotation))
            // Keep the whole sphere in view even at the peak of a reaction.
            let fit = min(1, 1.08 / max(0.01, abs(scaleX), abs(scaleY)))
            context.scaleBy(x: scaleX * fit, y: scaleY * fit)
            context.translateBy(x: -50, y: -50)

            let brightness = max(0, min(1, lamp))
            let horizontalGaze = CGFloat(max(-1, min(1, motion[1])))
            let verticalGaze = CGFloat(max(-1, min(1, motion[2])))
            let body = Path(ellipseIn: CGRect(x: 6, y: 6, width: 88, height: 88))
            context.fill(body, with: .radialGradient(Gradient(stops: [
                .init(color: Color(white: 0.95 + 0.03 * brightness), location: 0),
                .init(color: Color(white: 0.82 + 0.03 * brightness), location: 0.52),
                .init(color: Color(white: 0.53 + 0.03 * brightness), location: 1),
            ]), center: CGPoint(x: 38 + horizontalGaze * 2.5, y: 31 + verticalGaze * 1.5), startRadius: 0, endRadius: 68))
            context.clip(to: body)
            let blink = CGFloat(max(0.1, min(face == 9 ? 0.75 : 1, motion[0])))
            let eyeSize = CGFloat(max(0.85, min(1.15, eyeScale)))
            let eyeColor = Color(white: 0.09)
            for side: CGFloat in [-1, 1] {
                let eye = riumEyeRect(side: side, gazeX: horizontalGaze, gazeY: verticalGaze,
                                      openness: blink, scale: eyeSize)
                let eyeX = eye.midX, eyeY = eye.midY
                if face == 12 { continue }
                if face == 11 || face == 3 {
                    var cross = Path()
                    cross.move(to: CGPoint(x: eyeX - 8, y: eyeY - 9))
                    cross.addLine(to: CGPoint(x: eyeX + 8, y: eyeY + 9))
                    cross.move(to: CGPoint(x: eyeX + 8, y: eyeY - 9))
                    cross.addLine(to: CGPoint(x: eyeX - 8, y: eyeY + 9))
                    context.stroke(cross, with: .color(eyeColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else if [2, 4, 5, 6, 10].contains(face) {
                    var line = Path()
                    line.move(to: CGPoint(x: eyeX - 8, y: eyeY))
                    line.addQuadCurve(to: CGPoint(x: eyeX + 8, y: eyeY),
                                      control: CGPoint(x: eyeX, y: eyeY + ([4, 5, 10].contains(face) ? 5 : -8)))
                    context.stroke(line, with: .color(eyeColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                } else {
                    context.fill(Path(roundedRect: eye, cornerRadius: min(eye.width, eye.height) / 2, style: .circular),
                                 with: .linearGradient(Gradient(colors: [Color(white: 0.06), Color(white: 0.13)]),
                                                       startPoint: CGPoint(x: eye.midX, y: eye.minY),
                                                       endPoint: CGPoint(x: eye.midX, y: eye.maxY)))
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}
