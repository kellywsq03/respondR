import SwiftUI

struct HUDStatusView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            healthPanel
            scenarioPanel
            if let guidance = appModel.extinguisherGuidance {
                instructionPanel(guidance)
            }
        }
        .frame(width: 280, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var healthPanel: some View {
        HStack(spacing: 16) {
            Image("heart")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HEALTH")
                        .font(.headline)
                    Spacer()
                    Text("\(appModel.healthPercentage)%")
                        .font(.headline.monospacedDigit())
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.16))
                        Capsule()
                            .fill(healthColor.gradient)
                            .frame(width: proxy.size.width * appModel.health)
                    }
                }
                .frame(height: 12)
            }
            .frame(width: 184)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .glassBackgroundEffect()
        .shadow(
            color: appModel.isNearFire ? .red.opacity(0.7) : .clear,
            radius: appModel.isNearFire ? 16 : 0
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82),
            value: appModel.health
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
            value: appModel.isNearFire
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health")
        .accessibilityValue("\(appModel.healthPercentage) percent")
    }

    private var scenarioPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(appModel.totalCasualties > 0 ? "CASUALTIES" : "SCENARIO")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if appModel.totalCasualties > 0 {
                    Spacer()
                    Text(appModel.casualtyProgress)
                        .font(.headline.monospacedDigit())
                }
            }

            Text(appModel.missionGuidance)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 248, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .glassBackgroundEffect()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            appModel.totalCasualties > 0 ? "Casualty rescue progress" : "Scenario status"
        )
        .accessibilityValue(
            appModel.totalCasualties > 0
                ? "\(appModel.rescuedCasualties) of \(appModel.totalCasualties). \(appModel.missionGuidance)"
                : appModel.missionGuidance
        )
    }

    private func instructionPanel(_ guidance: String) -> some View {
        Text(guidance)
            .font(.callout.weight(.semibold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 248, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .glassBackgroundEffect()
            .accessibilityLabel("Fire extinguisher")
            .accessibilityValue(guidance)
    }

    private var healthColor: Color {
        if appModel.isNearFire { return .red }
        if appModel.health <= 0.25 { return .orange }
        return .green
    }
}

struct HUDTimerView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("TIME REMAINING")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appModel.formattedTimeRemaining)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(appModel.timeRemaining <= 60 ? .red : .primary)
                .contentTransition(.numericText(countsDown: true))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .glassBackgroundEffect()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time remaining")
        .accessibilityValue(appModel.formattedTimeRemaining)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
