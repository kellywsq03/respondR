import SwiftUI

struct ScenarioResultView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let outcome = appModel.scenarioOutcome {
                resultPanel(outcome)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.96).combined(with: .opacity)
                    )
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.84),
            value: appModel.scenarioPhase
        )
    }

    private func resultPanel(_ outcome: ScenarioSession.Outcome) -> some View {
        VStack(spacing: 24) {
            Image(systemName: outcome.isVictory ? "checkmark.seal.fill" : "arrow.counterclockwise.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(outcome.isVictory ? .green : .orange)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(outcome.isVictory ? "Congratulations!" : "Try again!")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(
                    outcome.isVictory
                        ? "You managed to rescue the casualties and escaped successfully!"
                        : "Remember to rescue the casualty and escape on time to save everybody!"
                )
                .font(.title3)
                .multilineTextAlignment(.center)

                if let reason = defeatReason(outcome.defeatReason) {
                    Text(reason)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 32) {
                resultMetric(label: "TIME USED", value: formattedTime(outcome.timeUsed))
                resultMetric(
                    label: "CASUALTIES",
                    value: "\(outcome.rescuedCount)/\(outcome.totalCasualties)"
                )
            }

            HStack(spacing: 16) {
                Button("End Training", role: .cancel) {
                    appModel.requestEndTraining()
                }
                .buttonStyle(.bordered)

                Button("Try Again") {
                    appModel.requestScenarioReset()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Press the Digital Crown to exit.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Press the Digital Crown to exit this screen")
        }
        .frame(width: 480)
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32))
        .glassBackgroundEffect()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(outcome.isVictory ? "Scenario victory" : "Scenario defeat")
    }

    private func resultMetric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(value)
    }

    private func defeatReason(_ reason: ScenarioSession.DefeatReason?) -> String? {
        switch reason {
        case .timeExpired:
            "Time ran out."
        case .healthDepleted:
            "Your health reached zero."
        case .casualtiesLeftBehind:
            appModel.remainingCasualties == 1
                ? "A casualty was left behind."
                : "Casualties were left behind."
        case nil:
            nil
        }
    }

    private func formattedTime(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, min(5 * 60, Int(duration.rounded(.down))))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
