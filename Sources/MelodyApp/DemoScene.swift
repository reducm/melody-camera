import SwiftUI
import MelodyCore

/// 内置矢量练习画面，所有元素均由代码绘制，不代表真实人物。
struct DemoScene: View {
    let scene: SceneKind
    var body: some View {
        Canvas { c, size in
            let w = size.width, h = size.height
            func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
                CGRect(x: x*w, y: y*h, width: width*w, height: height*h)
            }
            let sky = scene == .city ? Color(red: 0.60, green: 0.65, blue: 0.65) : Color(red: 0.73, green: 0.77, blue: 0.66)
            c.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [sky, Color(red: 0.9, green: 0.82, blue: 0.66)]), startPoint: .zero, endPoint: CGPoint(x:w,y:h)))
            if scene == .garden {
                for i in 0..<8 {
                    let x = Double(i) * 0.17 - 0.12
                    c.fill(Path(rect(x, 0, 0.027, 0.7)), with: .color(Color(red: 0.34, green: 0.39, blue: 0.25)))
                    c.fill(Path(ellipseIn: rect(x-0.12, -0.1 + Double(i%3)*0.05, 0.4, 0.45)), with: .color(Color(red: 0.30+Double(i%2)*0.06, green: 0.40, blue: 0.27).opacity(0.7)))
                }
                var road = Path(); road.move(to: CGPoint(x:w*0.46,y:h*0.46)); road.addLine(to: CGPoint(x:w*1.2,y:h)); road.addLine(to: CGPoint(x:w*0.05,y:h)); road.closeSubpath()
                c.fill(road, with: .color(Color(red:0.73,green:0.66,blue:0.51)))
                for i in 0..<20 {
                    c.fill(Path(ellipseIn: rect(Double((i*37)%100)/100, 0.67+Double(i%6)*0.065, 0.012, 0.008)), with: .color(.white.opacity(0.4)))
                }
            } else {
                c.fill(Path(rect(0,0,0.20,1)), with: .color(Color(red:0.39,green:0.42,blue:0.39)))
                c.fill(Path(rect(0.8,0,0.20,1)), with: .color(Color(red:0.54,green:0.51,blue:0.44)))
                for i in 0..<4 {
                    c.fill(Path(rect(0.25, Double(i)*0.19, 0.5, 0.013)), with: .color(.black.opacity(0.32)))
                }
                c.fill(Path(rect(0.49,0,0.015,0.82)), with: .color(.black.opacity(0.35)))
                if scene == .cafe {
                    c.fill(Path(ellipseIn: rect(0.55,0.71,0.7,0.1)), with: .color(Color(red:0.44,green:0.30,blue:0.22)))
                    c.fill(Path(rect(0.69,0.65,0.09,0.065)), with: .color(.white.opacity(0.8)))
                }
            }
            // 人物练习剪影，保持与真实人体检测明确分离。
            c.fill(Path(ellipseIn: rect(0.30,0.86,0.32,0.035)), with: .color(.black.opacity(0.17)))
            c.fill(Path(roundedRect: rect(0.39,0.58,0.058,0.285), cornerRadius: w*0.022), with: .color(Color(red:0.81,green:0.66,blue:0.52)))
            c.fill(Path(roundedRect: rect(0.49,0.58,0.058,0.285), cornerRadius: w*0.022), with: .color(Color(red:0.86,green:0.70,blue:0.56)))
            c.fill(Path(ellipseIn: rect(0.37,0.28,0.20,0.19)), with: .color(Color(red:0.20,green:0.17,blue:0.14)))
            c.fill(Path(ellipseIn: rect(0.403,0.31,0.13,0.116)), with: .color(Color(red:0.85,green:0.70,blue:0.56)))
            var dress = Path(); dress.move(to: CGPoint(x:w*0.40,y:h*0.425)); dress.addQuadCurve(to: CGPoint(x:w*0.31,y:h*0.67), control: CGPoint(x:w*0.35,y:h*0.51)); dress.addQuadCurve(to: CGPoint(x:w*0.62,y:h*0.67), control: CGPoint(x:w*0.46,y:h*0.72)); dress.addLine(to: CGPoint(x:w*0.535,y:h*0.425)); dress.closeSubpath()
            c.fill(dress, with: .color(Color(red:0.94,green:0.90,blue:0.78)))
            c.fill(Path(roundedRect: rect(0.34,0.44,0.038,0.18), cornerRadius: w*0.02), with: .color(Color(red:0.85,green:0.70,blue:0.56)))
            c.fill(Path(roundedRect: rect(0.55,0.44,0.035,0.17), cornerRadius: w*0.02), with: .color(Color(red:0.85,green:0.70,blue:0.56)))
        }
    }
}

struct CompositionOverlay: View {
    let subject: SubjectBox?
    let grid: Bool
    let opacity: Double
    var body: some View {
        Canvas { context, size in
            if grid {
                var lines = Path()
                for f in [1.0/3, 2.0/3] {
                    lines.move(to: CGPoint(x:size.width*f,y:0)); lines.addLine(to: CGPoint(x:size.width*f,y:size.height))
                    lines.move(to: CGPoint(x:0,y:size.height*f)); lines.addLine(to: CGPoint(x:size.width,y:size.height*f))
                }
                context.stroke(lines, with: .color(.white.opacity(0.38)), lineWidth: 0.7)
            }
            guard let b = subject else { return }
            let r = CGRect(x:b.x*size.width,y:b.y*size.height,width:b.width*size.width,height:b.height*size.height)
            context.stroke(Path(roundedRect:r,cornerRadius:12),with:.color(Color.melodyLime.opacity(opacity)),style:StrokeStyle(lineWidth:1.2,dash:[6,5]))
            let head = CGRect(x:r.midX-r.width*0.17,y:r.minY+r.height*0.025,width:r.width*0.34,height:r.height*0.16)
            context.stroke(Path(ellipseIn:head),with:.color(.white.opacity(opacity)),lineWidth:1.6)
            var body = Path()
            body.move(to:CGPoint(x:r.minX+r.width*0.2,y:r.minY+r.height*0.43))
            body.addQuadCurve(to:CGPoint(x:r.midX,y:r.minY+r.height*0.23),control:CGPoint(x:r.minX+r.width*0.22,y:r.minY+r.height*0.22))
            body.addQuadCurve(to:CGPoint(x:r.maxX-r.width*0.2,y:r.minY+r.height*0.43),control:CGPoint(x:r.maxX-r.width*0.22,y:r.minY+r.height*0.22))
            body.move(to:CGPoint(x:r.midX,y:r.minY+r.height*0.23)); body.addLine(to:CGPoint(x:r.midX,y:r.minY+r.height*0.60))
            body.addLine(to:CGPoint(x:r.minX+r.width*0.28,y:r.maxY-r.height*0.04))
            body.move(to:CGPoint(x:r.midX,y:r.minY+r.height*0.60)); body.addLine(to:CGPoint(x:r.maxX-r.width*0.28,y:r.maxY-r.height*0.04))
            context.stroke(body,with:.color(.white.opacity(opacity)),style:StrokeStyle(lineWidth:1.6,lineCap:.round,lineJoin:.round))
        }.allowsHitTesting(false)
    }
}
extension Color {
    static let melodyLime = Color(red:0.84,green:0.93,blue:0.64)
    static let melodyBackground = Color(red:0.07,green:0.09,blue:0.085)
    static let melodySurface = Color(red:0.12,green:0.14,blue:0.13)
    static let melodyMuted = Color(red:0.63,green:0.68,blue:0.64)
}
