import SwiftUI

struct LayoutSelectionView: View {
    @Binding var screen: AppScreen

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
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .fixedSize()
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

