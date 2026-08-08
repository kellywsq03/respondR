import SwiftUI

struct LayoutSelectionView: View {
    @Binding var screen: AppScreen

    var body: some View {
        BillboardedPanel {
            VStack(spacing: 32) {
                HStack {
                    Button {
                        screen = .phaseSelection
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.body.weight(.medium))
                    }
                    Spacer()
                    Text("Select Layout")
                        .font(.title2.bold())
                    Spacer()
                    Label("Back", systemImage: "chevron.left")
                        .font(.body.weight(.medium))
                        .opacity(0)
                }

                HStack(spacing: 24) {
                    ForEach(LayoutConfig.all) { layout in
                        Button {
                            screen = .liveScene(layout: layout.id)
                        } label: {
                            LayoutCard(layout: layout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(40)
            .glassBackgroundEffect()
        }
    }
}

private struct LayoutCard: View {
    let layout: LayoutConfig

    var body: some View {
        VStack(spacing: 12) {
            FloorPlan2DView(layout: layout)
                .frame(width: 200, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            Text(layout.name)
                .font(.headline)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .hoverEffect()
    }
}

// MARK: - 2D Top-Down Floor Plan

struct FloorPlan2DView: View {
    let layout: LayoutConfig

    var body: some View {
        Canvas { context, size in
            let padding: CGFloat = 14
            let scaleX = (size.width  - padding * 2) / CGFloat(layout.floorSize.x)
            let scaleZ = (size.height - padding * 2) / CGFloat(layout.floorSize.y)
            let scale  = min(scaleX, scaleZ)
            let cx     = size.width  / 2
            let cy     = size.height / 2

            // Floor fill
            let floorW = CGFloat(layout.floorSize.x) * scale
            let floorH = CGFloat(layout.floorSize.y) * scale
            let floorRect = CGRect(
                x: cx - floorW / 2,
                y: cy - floorH / 2,
                width: floorW,
                height: floorH
            )
            context.fill(
                Path(roundedRect: floorRect, cornerRadius: 2),
                with: .color(Color(white: 0.96))
            )

            // Grid lines on floor
            let gridStep: CGFloat = 20
            var gridPath = Path()
            let gx0 = cx - floorW / 2
            let gz0 = cy - floorH / 2
            var x = gx0
            while x <= gx0 + floorW {
                gridPath.move(to: CGPoint(x: x, y: gz0))
                gridPath.addLine(to: CGPoint(x: x, y: gz0 + floorH))
                x += gridStep
            }
            var z = gz0
            while z <= gz0 + floorH {
                gridPath.move(to: CGPoint(x: gx0, y: z))
                gridPath.addLine(to: CGPoint(x: gx0 + floorW, y: z))
                z += gridStep
            }
            context.stroke(gridPath, with: .color(Color(white: 0.82)), lineWidth: 0.5)

            // Floor border
            context.stroke(
                Path(roundedRect: floorRect, cornerRadius: 2),
                with: .color(Color(white: 0.5)),
                lineWidth: 1.2
            )

            // Walls
            for wall in layout.walls {
                let wallCX = CGFloat(wall.position.x) * scale + cx
                let wallCY = CGFloat(wall.position.z) * scale + cy

                let wallW: CGFloat
                let wallH: CGFloat
                if abs(wall.rotation) < 0.1 {
                    wallW = CGFloat(wall.size.x) * scale
                    wallH = max(CGFloat(wall.size.z) * scale, 3)
                } else {
                    wallW = max(CGFloat(wall.size.z) * scale, 3)
                    wallH = CGFloat(wall.size.x) * scale
                }

                let wallRect = CGRect(
                    x: wallCX - wallW / 2,
                    y: wallCY - wallH / 2,
                    width: wallW,
                    height: wallH
                )
                context.fill(Path(wallRect), with: .color(Color(white: 0.25)))
            }
        }
        .background(Color(white: 0.92))
    }
}
