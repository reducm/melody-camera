import SwiftUI
import MelodyCore

struct SubjectOutlineView: View {
    let outline: SubjectOutline
    var target: SubjectBox? = nil
    var opacity: Double = 1
    var body: some View {
        Canvas { context, size in
            let displayed = target.flatMap { try? outline.placed(in: $0, canvasAspect: size.width/size.height) } ?? outline
            for points in displayed.paths {
                var path = Path()
                guard let first = points.first else { continue }
                path.move(to: CGPoint(x: first.x*size.width, y: first.y*size.height))
                for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x*size.width, y: point.y*size.height)) }
                path.closeSubpath()
                context.fill(path, with: .color(Color.melodyLime.opacity(0.12*opacity)))
                context.stroke(path, with: .color(Color.melodyLime.opacity(opacity)), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }.allowsHitTesting(false)
    }
}
struct ShotTemplatePreview: View {
    let plan: ShotPlan
    let outline: SubjectOutline?
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Color.melodyBackground
                CompositionOverlay(subject: plan.subject, grid: true, opacity: 0.7, showPerson: false)
                if let outline { SubjectOutlineView(outline: outline, target: plan.subject) }
            }.aspectRatio(0.75, contentMode: .fit).frame(width: 132).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                if let viewpoint = plan.viewpoint {
                    Label(viewpoint.title, systemImage: viewpoint == .low ? "arrow.up" : (viewpoint == .high || viewpoint == .overhead ? "arrow.down" : "camera.rotate"))
                        .font(.subheadline.bold())
                    CameraPositionDiagram(viewpoint: viewpoint).frame(height: 66)
                    Text("机位示意 · 圆点为主体").font(.caption2).foregroundStyle(.secondary)
                }
                Text("主体位置与留白").font(.caption)
                Text(outline == nil ? "未提取到轮廓，只显示目标范围。" : "描边来自当前照片，保持原比例。机位变化按文字执行，未生成新视角照片。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// 受控的机位示意，圆点代表主体，不伪装成单图恢复的物体新视角。
private struct CameraPositionDiagram: View {
    let viewpoint: CameraViewpoint
    var body: some View {
        Canvas { context, size in
            let side = [.low, .high, .overhead].contains(viewpoint)
            let subject = CGPoint(x: size.width * 0.45, y: size.height * (side ? 0.65 : 0.28))
            let camera: CGPoint
            switch viewpoint {
            case .low: camera = CGPoint(x:size.width*0.9,y:size.height*0.85)
            case .high: camera = CGPoint(x:size.width*0.9,y:size.height*0.1)
            case .overhead: camera = CGPoint(x:subject.x,y:4)
            case .left45: camera = CGPoint(x:size.width*0.1,y:size.height*0.85)
            case .right45: camera = CGPoint(x:size.width*0.9,y:size.height*0.85)
            case .eyeLevel: camera = CGPoint(x:subject.x,y:size.height*0.9)
            }
            var sight = Path(); sight.move(to:camera); sight.addLine(to:subject)
            context.stroke(sight,with:.color(.white.opacity(0.4)),style:StrokeStyle(lineWidth:1,dash:[3,3]))
            context.fill(Path(ellipseIn:CGRect(x:subject.x-7,y:subject.y-7,width:14,height:14)),with:.color(Color.melodyLime))
            context.draw(Image(systemName:"camera.fill"),at:camera)
        }.padding(.bottom,12).accessibilityLabel("\(viewpoint.title)，机位示意，圆点代表主体")
    }
}
