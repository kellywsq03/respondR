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

                Text("Phase 2 Incident Response")
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
                            // Fire mode is the full scenario, so the control
                            // window gets out of the way. Wireframe is the
                            // room-mapping tool — keep the window open so the
                            // Room Map controls stay reachable while sweeping.
                            if appModel.mode == .fire {
                                dismissWindow(id: AppSceneID.mainWindow)
                            }
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

            GroupBox("Room Map") {
                VStack(alignment: .leading, spacing: 8) {
                    if let count = appModel.roomMapSurfaceCount {
                        Label(
                            appModel.roomMapRestored
                                ? "Map active (\(count) surfaces)"
                                : "Map saved (\(count) surfaces)"
                                    + (appModel.immersiveSpaceOpen ? " — locating room…" : ""),
                            systemImage: appModel.roomMapRestored
                                ? "map.fill" : "location.magnifyingglass"
                        )
                        .font(.footnote)
                    } else {
                        Text(
                            "No room map saved. Enter the mesh in Wireframe mode, sweep the whole room, then save. Every later session restores it so fires can start anywhere in the room."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Save Room Map") {
                            Task {
                                appModel.statusMessage =
                                    await appModel.saveRoomMapHandler?()
                                    ?? "Enter the mesh first."
                            }
                        }
                        .disabled(!appModel.immersiveSpaceOpen)

                        Button("Delete Map", role: .destructive) {
                            Task {
                                if let handler = appModel.deleteRoomMapHandler {
                                    appModel.statusMessage = await handler()
                                } else {
                                    RoomMapStore.delete()
                                    appModel.roomMapSurfaceCount = nil
                                    appModel.statusMessage = "Room map deleted."
                                }
                            }
                        }
                        .disabled(!appModel.hasRoomMap)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appModel.mode == .fire {
                GroupBox("Responder Status") {
                    VStack(spacing: 8) {
                        LabeledContent("Health", value: "\(appModel.healthPercentage)%")
                        ProgressView(value: appModel.health)
                            .tint(appModel.isNearFire ? .red : .green)
                        LabeledContent("Time", value: appModel.formattedTimeRemaining)
                            .monospacedDigit()
                        LabeledContent("Casualties", value: appModel.casualtyProgress)
                            .monospacedDigit()
                        LabeledContent("Scenario", value: appModel.scenarioPhaseLabel)
                        if appModel.isNearFire {
                            Label("Fire proximity warning", systemImage: "flame.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button("Reset Scenario") {
                    appModel.requestScenarioReset()
                }
                .disabled(!appModel.immersiveSpaceOpen)

#if DEBUG
                GroupBox("Debug Event Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gabe and fires use temporary scanned-surface placement. The exit and anchor map are not loaded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Reach Exit") {
                            appModel.recordExitReached()
                        }
                        .disabled(!appModel.isScenarioActive)

                        Button("Expire Timer") {
                            appModel.debugExpireTimer()
                        }
                        .disabled(!appModel.isScenarioActive)

                        Button("Deplete Health") {
                            appModel.debugDepleteHealth()
                        }
                        .disabled(!appModel.isScenarioActive)
                    }
                }
#endif

#if DEBUG
                Text("A fire breaks out on its own shortly after the scenario starts.")
                    .font(.footnote).foregroundStyle(.secondary)
#endif
            }

            if let status = appModel.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }

            if let error = appModel.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(32)
        .onChange(of: appModel.endTrainingTrigger) { _, _ in
            Task { await returnToPhaseSelection() }
        }
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
        appModel.stopScenario()
        screen = .phaseSelection
        isReturningToPhaseSelection = false
    }
}
