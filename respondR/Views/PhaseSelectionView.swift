import SwiftUI

struct PhaseSelectionView: View {
    @Binding var screen: AppScreen

    var body: some View {
        BillboardedPanel {
            VStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("RespondR")
                        .font(.system(size: 48, weight: .bold))
                    Text("Firefighter Training Platform")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("Select Training Phase")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 32) {
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

                    PhaseCard(
                        phase: "Phase II",
                        subtitle: "Live Incident Response",
                        icon: "flame.fill",
                        locked: true
                    )
                }
            }
            .padding(56)
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
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(locked ? .secondary : .primary)
                    .frame(width: 60, height: 60)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .offset(x: 8, y: -8)
                }
            }

            VStack(spacing: 6) {
                Text(phase)
                    .font(.title.bold())
                Text(subtitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if locked {
                Text("Coming Soon")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .frame(width: 240, height: 180)
        .padding(24)
        .background(.regularMaterial.opacity(locked ? 0.3 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    locked ? Color.secondary.opacity(0.2) : Color.white.opacity(0.3),
                    lineWidth: 1
                )
        )
        .opacity(locked ? 0.45 : 1.0)
        .saturation(locked ? 0.0 : 1.0)
    }
}
