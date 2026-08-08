import Foundation

enum AppScreen: Equatable {
    case phaseSelection
    case layoutSelection
    case liveScene(layout: Int)
<<<<<<< HEAD
    case phaseTwo
=======
    case liveSceneAsset(assetName: String)
>>>>>>> 2838685 (add new live scene type)
}
