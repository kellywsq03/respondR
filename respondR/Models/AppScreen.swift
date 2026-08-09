import Foundation

enum AppScreen: Equatable {
    case phaseSelection
    case layoutSelection
    case liveScene(layout: Int)
    case phaseTwo
    case liveSceneAsset(assetName: String)
}
