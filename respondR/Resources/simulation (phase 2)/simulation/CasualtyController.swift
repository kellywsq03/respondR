import Foundation
import RealityKit
import simd

/// Owns the single mapless Phase 2 casualty from delayed world spawn through
/// one-pinch rescue and the lower-left carried presentation.
@MainActor
final class CasualtyController {
    typealias DeviceTransformProvider = @MainActor () -> simd_float4x4?
    typealias FloorPositionProvider = @MainActor (SIMD3<Float>) -> SIMD3<Float>?

    enum Phase {
        case waiting
        case available
        case carried
    }

    var onError: ((String) -> Void)?
    var onWaitingForFloor: (() -> Void)?
    var onDidSpawn: (() -> Void)?

    private let sceneRoot: Entity
    private var modelTemplate: Entity?
    private var preloadTask: Task<Void, Never>?
    private var preloadError: String?
    private var spawnTask: Task<Void, Never>?
    private var casualtyEntity: Entity?
    private var lastDeviceTransform: simd_float4x4?
    private(set) var phase: Phase = .waiting

    /// World position of the spawned, not-yet-rescued casualty, for the
    /// floating "VICTIM" pointer label.
    var availableWorldPosition: SIMD3<Float>? {
        guard phase == .available else { return nil }
        return casualtyEntity?.position(relativeTo: nil)
    }

    init(sceneRoot: Entity) {
        self.sceneRoot = sceneRoot
    }

    func preloadAsset() {
        guard modelTemplate == nil, preloadTask == nil else { return }
        preloadError = nil

        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { preloadTask = nil }

            do {
                modelTemplate = try await Entity(named: "gabe", in: .main)
            } catch is CancellationError {
                return
            } catch {
                preloadError = error.localizedDescription
            }
        }
    }

    /// Begins the fixed delay after the extinguisher has actually spawned, then
    /// waits for a valid tracked head pose and a suitable scanned floor point.
    func scheduleSpawn(
        deviceTransform: @escaping DeviceTransformProvider,
        floorPosition: @escaping FloorPositionProvider
    ) {
        clearAttempt()
        preloadAsset()
        let pendingPreload = preloadTask

        spawnTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(5))
                if let pendingPreload {
                    await pendingPreload.value
                }
                try Task.checkCancellation()

                guard let modelTemplate else {
                    throw CasualtyError.assetLoadFailed(
                        preloadError ?? "The asset could not be loaded."
                    )
                }

                var reportedFloorWait = false
                while !Task.isCancelled {
                    if let pose = deviceTransform() {
                        let headPosition = SIMD3<Float>(
                            pose.columns.3.x,
                            pose.columns.3.y,
                            pose.columns.3.z
                        )
                        if let position = floorPosition(headPosition) {
                            install(modelTemplate.clone(recursive: true), at: position)
                            spawnTask = nil
                            return
                        }
                    }

                    if !reportedFloorWait {
                        reportedFloorWait = true
                        onWaitingForFloor?()
                    }
                    try await Task.sleep(for: .milliseconds(250))
                }
            } catch is CancellationError {
                return
            } catch {
                spawnTask = nil
                onError?("Couldn't load casualty Gabe: \(error.localizedDescription)")
            }
        }
    }

    func contains(_ entity: Entity) -> Bool {
        guard let casualtyEntity else { return false }
        var candidate: Entity? = entity
        while let current = candidate {
            if current === casualtyEntity { return true }
            candidate = current.parent
        }
        return false
    }

    @discardableResult
    func completeRescue() -> Bool {
        guard phase == .available, let casualtyEntity else { return false }
        phase = .carried
        casualtyEntity.isEnabled = false
        Self.disableInteraction(on: casualtyEntity)
        if let lastDeviceTransform {
            applyCarriedTransform(lastDeviceTransform, to: casualtyEntity)
        }
        return true
    }

    /// Keeps carried Gabe in a stable lower-left head-relative position. A
    /// tracking interruption retains the last valid pose.
    func update(deviceTransform: simd_float4x4?) {
        if let deviceTransform {
            lastDeviceTransform = deviceTransform
        }
        guard phase == .carried,
              let casualtyEntity,
              let lastDeviceTransform else {
            return
        }
        applyCarriedTransform(lastDeviceTransform, to: casualtyEntity)
    }

    func resetForAwaitingSpawn() {
        clearAttempt()
    }

    func cancel() {
        clearAttempt()
        preloadTask?.cancel()
        preloadTask = nil
        modelTemplate = nil
        preloadError = nil
    }

    private func install(_ model: Entity, at floorPosition: SIMD3<Float>) {
        let container = Entity()
        container.name = "Phase 2 casualty Gabe"
        container.addChild(model)

        let bounds = container.visualBounds(relativeTo: container)
        model.position -= SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z)
        model.generateCollisionShapes(recursive: true)
        Self.enableInteraction(on: model)

        // Generous expanded pickup target (like the extinguisher's): the model's
        // own collision hugs a small lying figure, which makes gaze targeting
        // fussy against the surrounding room mesh.
        let centeredBounds = container.visualBounds(relativeTo: container)
        let proxy = Entity()
        proxy.name = "Casualty expanded rescue target"
        proxy.position = centeredBounds.center
        proxy.components.set(
            CollisionComponent(
                shapes: [
                    ShapeResource.generateBox(
                        size: simd_max(centeredBounds.extents, SIMD3<Float>(repeating: 0.25)) * 2
                    )
                ]
            )
        )
        proxy.components.set(InputTargetComponent())
        proxy.components.set(HoverEffectComponent())
        container.addChild(proxy)

        container.position = floorPosition
        container.orientation = simd_quatf(
            angle: Float.random(in: -.pi ... .pi),
            axis: SIMD3<Float>(0, 1, 0)
        )
        sceneRoot.addChild(container)
        casualtyEntity = container
        phase = .available
        onDidSpawn?()
    }

    private func applyCarriedTransform(_ deviceTransform: simd_float4x4, to entity: Entity) {
        var transform = Transform(
            matrix: deviceTransform * Self.translation(x: -0.32, y: -0.35, z: -0.65)
        )
        transform.scale = SIMD3<Float>(repeating: 0.2)
        entity.transform = transform
        entity.isEnabled = true
    }

    private func clearAttempt() {
        spawnTask?.cancel()
        spawnTask = nil
        casualtyEntity?.removeFromParent()
        casualtyEntity = nil
        lastDeviceTransform = nil
        phase = .waiting
    }

    private static func enableInteraction(on entity: Entity) {
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent())
        for child in entity.children {
            enableInteraction(on: child)
        }
    }

    private static func disableInteraction(on entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        for child in entity.children {
            disableInteraction(on: child)
        }
    }

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
}

private enum CasualtyError: LocalizedError {
    case assetLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .assetLoadFailed(let message):
            "The Gabe casualty asset could not be loaded: \(message)"
        }
    }
}
