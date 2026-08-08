import SwiftUI

struct ControlWindowView: View {
    @Binding var screen: AppScreen
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isReturningToPhaseSelection = false

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 20) {
            HStack {
                Button {
                    Task { await returnToPhaseSelection() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(isReturningToPhaseSelection)

                Spacer()

                Text("Spatial Meshing")
                    .font(.largeTitle)

                Spacer()

                Label("Back", systemImage: "chevron.left")
                    .hidden()
            }

            Picker("Mode", selection: $appModel.mode) {
                ForEach(AppModel.Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .disabled(appModel.immersiveSpaceOpen)

            if !appModel.isSupported {
                Text("Scene reconstruction isn't available here. Run on a physical Apple Vision Pro to see the mesh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(appModel.immersiveSpaceOpen ? "Exit Mesh" : "Enter Mesh") {
                Task {
                    if appModel.immersiveSpaceOpen {
                        await dismissImmersiveSpace()
                        appModel.immersiveSpaceOpen = false
                    } else {
                        print("MeshDebug: Enter Mesh tapped, opening MeshSpace…")
                        let result = await openImmersiveSpace(id: AppSceneID.meshSpace)
                        print("MeshDebug: openImmersiveSpace result = \(result)")
                        switch result {
                        case .opened:
                            appModel.immersiveSpaceOpen = true
                            appModel.errorMessage = nil
                        case .userCancelled:
                            appModel.immersiveSpaceOpen = false
                            appModel.errorMessage = "Open was cancelled."
                        case .error:
                            appModel.immersiveSpaceOpen = false
                            appModel.errorMessage = "Couldn't open the mesh space (.error)."
                        @unknown default:
                            appModel.immersiveSpaceOpen = false
                            appModel.errorMessage = "Open returned an unknown result."
                        }
                    }
                }
            }
            .disabled(!appModel.isSupported)

            Toggle("Show Mesh", isOn: $appModel.meshVisible)
                .disabled(!appModel.immersiveSpaceOpen)

            ColorPicker("Wireframe Color",
                        selection: $appModel.wireframeColor,
                        supportsOpacity: false)
                .disabled(!appModel.immersiveSpaceOpen)

            Button("Export Room (.usdc)") {
                appModel.statusMessage = appModel.exportHandler?()
                    ?? "Enter the mesh first."
            }
            .disabled(!appModel.immersiveSpaceOpen)

            if appModel.mode == .fire {
                GroupBox("Responder Status") {
                    VStack(spacing: 8) {
                        LabeledContent("Health", value: "\(appModel.healthPercentage)%")
                        ProgressView(value: appModel.health)
                            .tint(appModel.isNearFire ? .red : .green)
                        LabeledContent("Time", value: appModel.formattedTimeRemaining)
                            .monospacedDigit()
                        if appModel.isNearFire {
                            Label("Fire proximity warning", systemImage: "flame.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button("Reset Fire") {
                    appModel.resetFireTrigger += 1
                }
                .disabled(!appModel.immersiveSpaceOpen)

                Button("Reset HUD / Timer") {
                    appModel.resetHUD()
                    if appModel.immersiveSpaceOpen { appModel.startTimer() }
                }

                Text("Tap a surface to ignite.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let status = appModel.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }

            if let error = appModel.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(32)
    }

    private func returnToPhaseSelection() async {
        guard !isReturningToPhaseSelection else { return }
        isReturningToPhaseSelection = true

        if appModel.immersiveSpaceOpen {
            await dismissImmersiveSpace()
            appModel.immersiveSpaceOpen = false
        }

        appModel.statusMessage = nil
        appModel.errorMessage = nil
        screen = .phaseSelection
        dismissWindow(id: AppSceneID.phase2Controls)
        isReturningToPhaseSelection = false
    }
}
