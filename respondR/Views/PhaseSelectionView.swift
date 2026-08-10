import SwiftUI

struct PhaseSelectionView: View {
    @Binding var screen: AppScreen

    var body: some View {
        BillboardedPanel(initialScale: 5.5) {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text("RespondR")
                        .font(.system(size: 18, weight: .bold))
                    Text("Firefighter Training Platform")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

                Text("Select Training Phase")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        screen = .layoutSelection
                    } label: {
                        PhaseCard(
                            phase: "Phase I",
                            subtitle: "Room Familiarization",
                            icon: "house.fill",
                            locked: false
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        screen = .phaseTwo
                    } label: {
                        PhaseCard(
                            phase: "Phase II",
                            subtitle: "Live Incident Response",
                            icon: "flame.fill",
                            locked: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .fixedSize()
            .glassBackgroundEffect()
        }
    }
}

private struct PhaseCard: View {
    let phase: String
    let subtitle: String
    let icon: String
    let locked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(locked ? .secondary : .primary)
                    .frame(width: 28, height: 28)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(x: 4, y: -4)
                }
            }

            VStack(spacing: 2) {
                Text(phase)
                    .font(.system(size: 12, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 7))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if locked {
                Text("Coming Soon")
                    .font(.system(size: 6))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 80, height: 80)
        .padding(6)
        .background(.regularMaterial.opacity(locked ? 0.3 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    locked ? Color.secondary.opacity(0.2) : Color.white.opacity(0.3),
                    lineWidth: 0.5
                )
        )
        .opacity(locked ? 0.45 : 1.0)
        .saturation(locked ? 0.0 : 1.0)
    }
}
