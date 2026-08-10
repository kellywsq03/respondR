import AVFAudio
import Foundation
import RealityKit
import UIKit
import simd

/// Owns the Phase 2 extinguisher asset, spray visual, spatial hiss, and session lifecycle.
@MainActor
final class FireExtinguisherController {
    typealias DeviceTransformProvider = @MainActor () -> simd_float4x4?

    static let targetHeight: Float = 0.55
    /// Length of the visual cone and the distance ahead of the learner the
    /// spray converges on.
    static let sprayLength: Float = 2.5
    /// How far the extinguishing volume actually reaches from the nozzle.
    static let sprayReach: Float = 3.5
    static let sprayHalfAngle: Float = 25 * .pi / 180
    /// The learner must be beside the extinguisher to pick it up.
    static let pickUpDistance: Float = 1.0

    var onStateChange: ((FireExtinguisherSession.Phase, Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onDidSpawn: (() -> Void)?

    private let sceneRoot: Entity
    private let sprayEntity: ModelEntity?
    private var extinguisherEntity: Entity?
    private var nozzleEntity: Entity?
    private var modelTemplate: Entity?
    private var preloadTask: Task<Void, Never>?
    private var preloadError: String?
    private var spawnTask: Task<Void, Never>?
    private var hissController: AudioGeneratorController?
    private var session = FireExtinguisherSession()
    private var currentSprayCone: SprayCone?
    private var sprayMeshError: String?

    var phase: FireExtinguisherSession.Phase { session.phase }
    var isSpraying: Bool { session.isSpraying }
    /// World position of the spawned, not-yet-picked-up extinguisher, for the
    /// floating "EXTINGUISHER" pointer label.
    var availableWorldPosition: SIMD3<Float>? {
        guard session.phase == .available else { return nil }
        return extinguisherEntity?.position(relativeTo: nil)
    }
    var activeSprayCone: SprayCone? {
        session.isSpraying ? currentSprayCone : nil
    }

    init(sceneRoot: Entity) {
        self.sceneRoot = sceneRoot

        do {
            let sprayEntity = try Self.makeSprayEntity()
            sprayEntity.isEnabled = false
            self.sprayEntity = sprayEntity
        } catch {
            sprayEntity = nil
            sprayMeshError = "Couldn't create the extinguisher spray cone: \(error.localizedDescription)"
        }
    }

    /// Loads and caches the asset without adding it to the immersive scene or
    /// starting the five-second post-fire delay.
    func preloadAsset() {
        guard modelTemplate == nil, preloadTask == nil else { return }
        preloadError = nil

        preloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { preloadTask = nil }

            do {
                modelTemplate = try await Entity(named: "Fire_Extinguisher", in: .main)
            } catch is CancellationError {
                return
            } catch {
                preloadError = error.localizedDescription
            }
        }
    }

    func scheduleSpawn(deviceTransform: @escaping DeviceTransformProvider) {
        clearAttempt()
        notifyStateChange()

        if let sprayMeshError {
            onError?(sprayMeshError)
        }

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
                    throw FireExtinguisherError.assetLoadFailed(
                        preloadError ?? "The asset could not be loaded."
                    )
                }
                let loadedModel = modelTemplate.clone(recursive: true)

                var devicePose = deviceTransform()
                while devicePose == nil {
                    try await Task.sleep(for: .milliseconds(100))
                    try Task.checkCancellation()
                    devicePose = deviceTransform()
                }

                guard let devicePose else { return }
                try install(loadedModel, at: devicePose)
                spawnTask = nil
            } catch is CancellationError {
                return
            } catch {
                spawnTask = nil
                onError?("Couldn't load the fire extinguisher: \(error.localizedDescription)")
            }
        }
    }

    /// Clears one attempt while retaining a successfully preloaded template for
    /// the next fire-start event.
    func resetForAwaitingFireStart() {
        clearAttempt()
        notifyStateChange()
    }

    func contains(_ entity: Entity) -> Bool {
        guard let extinguisherEntity else { return false }
        var candidate: Entity? = entity
        while let current = candidate {
            if current === extinguisherEntity { return true }
            candidate = current.parent
        }
        return false
    }

    @discardableResult
    func pickUp() -> Bool {
        let didPickUp = session.pickUp()
        if didPickUp {
            // The held bottle rides directly in front of the face. Leaving its
            // collision/input targeting active would intercept the gaze for
            // everything the learner looks at from then on — most importantly
            // the victim's rescue button.
            if let extinguisherEntity {
                Self.disableInteraction(on: extinguisherEntity)
            }
            notifyStateChange()
        }
        return didPickUp
    }

    @discardableResult
    func beginSpray() -> Bool {
        guard currentSprayCone != nil, session.beginSpray() else { return false }
        sprayEntity?.isEnabled = true
        hissController?.play()
        notifyStateChange()
        return true
    }

    func endSpray() {
        guard session.isSpraying else { return }
        session.endSpray()
        sprayEntity?.isEnabled = false
        hissController?.stop()
        notifyStateChange()
    }

    func update(deviceTransform: simd_float4x4?) {
        guard session.phase == .equipped, let deviceTransform else {
            currentSprayCone = nil
            if session.isSpraying {
                endSpray()
            }
            return
        }

        extinguisherEntity?.transform = Transform(
            matrix: deviceTransform * Self.translation(x: 0.32, y: -0.38, z: -0.60)
        )

        guard let nozzleEntity else {
            currentSprayCone = nil
            return
        }

        // Converge the spray on what the learner is LOOKING at, rather than
        // firing parallel to their gaze. The nozzle sits ~0.5 m to the lower
        // right of the head, so a parallel cone only covered fires in a narrow
        // 1.7-2.6 m band — anything you walked up to fell outside it.
        let apex = nozzleEntity.convert(position: .zero, to: nil)
        let headPosition = SIMD3<Float>(
            deviceTransform.columns.3.x,
            deviceTransform.columns.3.y,
            deviceTransform.columns.3.z
        )
        let gazeForward = -simd_normalize(
            SIMD3<Float>(
                deviceTransform.columns.2.x,
                deviceTransform.columns.2.y,
                deviceTransform.columns.2.z
            )
        )
        let aimPoint = headPosition + gazeForward * Self.sprayLength
        let direction = aimPoint - apex
        currentSprayCone = SprayCone(
            apex: apex,
            direction: direction,
            maxDistance: Self.sprayReach,
            halfAngleRadians: Self.sprayHalfAngle
        )

        // Point the visible cone the same way so the spray reads correctly.
        if let sprayEntity, simd_length_squared(direction) > 0 {
            sprayEntity.setOrientation(
                simd_quatf(from: SIMD3<Float>(0, 0, -1), to: simd_normalize(direction)),
                relativeTo: nil
            )
        }
    }

    func cancel() {
        clearAttempt()
        preloadTask?.cancel()
        preloadTask = nil
        modelTemplate = nil
        preloadError = nil
        notifyStateChange()
    }

    private func install(_ model: Entity, at deviceTransform: simd_float4x4) throws {
        let container = Entity()
        container.name = "Phase 2 fire extinguisher"
        container.addChild(model)

        let authoredBounds = container.visualBounds(relativeTo: container)
        guard let uniformScale = ExtinguisherSizing.uniformScale(
            currentHeight: authoredBounds.extents.y,
            targetHeight: Self.targetHeight
        ) else {
            throw FireExtinguisherError.invalidAssetBounds
        }

        model.scale *= SIMD3<Float>(repeating: uniformScale)
        let normalizedBounds = container.visualBounds(relativeTo: container)
        model.position -= normalizedBounds.center
        let centeredBounds = container.visualBounds(relativeTo: container)
        model.generateCollisionShapes(recursive: true)
        Self.enableInteraction(on: model)

        let interactionProxy = Entity()
        interactionProxy.name = "Fire extinguisher expanded pickup target"
        interactionProxy.position = centeredBounds.center
        interactionProxy.components.set(
            CollisionComponent(
                shapes: [ShapeResource.generateBox(size: centeredBounds.extents * 2)]
            )
        )
        interactionProxy.components.set(InputTargetComponent())
        // No HoverEffectComponent: hover on invisible geometry contends with
        // the floating label button's own system hover for the gaze.
        container.addChild(interactionProxy)

        let nozzle = Entity()
        nozzle.name = "Fire extinguisher hose nozzle"
        nozzle.position = SIMD3<Float>(
            centeredBounds.min.x + centeredBounds.extents.x * 0.18,
            centeredBounds.min.y + centeredBounds.extents.y * 0.10,
            centeredBounds.min.z - 0.01
        )
        container.addChild(nozzle)
        if let sprayEntity {
            sprayEntity.transform = .identity
            nozzle.addChild(sprayEntity)
        }
        nozzleEntity = nozzle

        container.transform = Transform(
            matrix: deviceTransform * Self.translation(x: 0.25, y: -0.40, z: -0.90)
        )
        sceneRoot.addChild(container)
        extinguisherEntity = container
        prepareHiss(on: container)

        session.didSpawn()
        notifyStateChange()
        onDidSpawn?()
    }

    private func prepareHiss(on entity: Entity) {
        do {
            let controller = try entity.prepareAudio(
                configuration: AudioGeneratorConfiguration(),
                Self.makeHissRenderBlock()
            )
            controller.gain = -10
            hissController = controller
        } catch {
            hissController = nil
            onError?("Extinguisher audio is unavailable: \(error.localizedDescription)")
        }
    }

    private func clearAttempt() {
        spawnTask?.cancel()
        spawnTask = nil
        hissController?.stop()
        hissController = nil
        sprayEntity?.isEnabled = false
        sprayEntity?.removeFromParent()
        nozzleEntity = nil
        extinguisherEntity?.removeFromParent()
        extinguisherEntity = nil
        currentSprayCone = nil
        session.reset()
    }

    private func notifyStateChange() {
        onStateChange?(session.phase, session.isSpraying)
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

    private static func makeSprayEntity() throws -> ModelEntity {
        let segments = 20
        let radius = sprayLength * tan(sprayHalfAngle)
        var positions: [SIMD3<Float>] = [.zero]
        var indices: [UInt32] = []

        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            positions.append(
                SIMD3<Float>(cos(angle) * radius, sin(angle) * radius, -sprayLength)
            )
        }

        for index in 0..<segments {
            let current = UInt32(index + 1)
            let next = UInt32((index + 1) % segments + 1)
            indices.append(contentsOf: [0, next, current, 0, current, next])
        }

        var descriptor = MeshDescriptor(name: "extinguisher-spray-cone")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        let mesh = try MeshResource.generate(from: [descriptor])
        let material = UnlitMaterial(color: UIColor.white.withAlphaComponent(0.45))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Active extinguisher spray cone"
        return entity
    }

    private static func makeHissRenderBlock() -> AVAudioSourceNodeRenderBlock {
        var randomState: UInt32 = 0xA341_316C
        var smoothedSample: Float = 0

        return { isSilence, _, frameCount, outputData in
            isSilence.pointee = false
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)

            for frame in 0..<Int(frameCount) {
                randomState = 1_664_525 &* randomState &+ 1_013_904_223
                let whiteNoise = Float(Int32(bitPattern: randomState)) / Float(Int32.max)
                smoothedSample += 0.18 * (whiteNoise - smoothedSample)
                let hiss = (whiteNoise - smoothedSample) * 0.12

                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                        continue
                    }
                    data[frame] = hiss
                }
            }
            return noErr
        }
    }

    private static func translation(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4<Float>(x, y, z, 1)
        return matrix
    }
}

private enum FireExtinguisherError: LocalizedError {
    case invalidAssetBounds
    case assetLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAssetBounds:
            "The fire extinguisher asset has invalid visual bounds."
        case .assetLoadFailed(let message):
            "The fire extinguisher asset could not be loaded: \(message)"
        }
    }
}
