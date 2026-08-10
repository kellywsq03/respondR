import SwiftUI

struct LayoutSelectionView: View {
    @Binding var screen: AppScreen
    @Environment(SceneViewModel.self) var viewModel

    var body: some View {
        BillboardedPanel(initialScale: 7.5) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        screen = .phaseSelection
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .hoverEffect()

                    Text("Select Layout")
                        .font(.caption.weight(.bold))
                }

                HStack(spacing: 5) {
                    ForEach(LayoutConfig.all) { layout in
                        Button {
                            screen = .liveScene(layout: layout.id)
                        } label: {
                            Text(layout.name)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .frame(width: 56, height: 38)
                                .background(.regularMaterial)
                                .hoverEffect()
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Scanned assets
                if !viewModel.preloadedAssetNames.isEmpty {
                    VStack(spacing: 12) {
                        Text("Scanned Assets")
                            .font(.system(size: 10, weight: .semibold))

                        HStack(spacing: 16) {
                            ForEach(
                                viewModel.preloadedAssetNames,
                                id: \.self
                            ) { assetName in
                                Button {
                                    screen = .liveSceneAsset(assetName: assetName)
                                } label: {
                                    DownloadedAssetCard(assetName: assetName)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .fixedSize()
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct DownloadedAssetCard: View {
    let assetName: String

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.16))

                Image(systemName: "cube.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, height: 38)

            Text(assetName)
                .font(.system(size: 8, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)

        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .hoverEffect()
    }
}

private struct LayoutCard: View {
    let layout: LayoutConfig

    var body: some View {
        VStack(spacing: 3) {
            FloorPlan2DView(layout: layout)
                .frame(width: 56, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
            Text(layout.name)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
        }
        .padding(4)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
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
