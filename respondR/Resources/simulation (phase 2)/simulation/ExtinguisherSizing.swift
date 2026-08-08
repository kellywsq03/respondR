import Foundation

enum ExtinguisherSizing {
    static func uniformScale(currentHeight: Float, targetHeight: Float) -> Float? {
        guard currentHeight.isFinite,
              targetHeight.isFinite,
              currentHeight > 0,
              targetHeight > 0 else {
            return nil
        }
        return targetHeight / currentHeight
    }
}
