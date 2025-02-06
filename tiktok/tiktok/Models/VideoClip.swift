import AVFoundation
import UIKit

struct VideoClip: Identifiable {
    let id: UUID
    let asset: AVAsset
    var startTime: Double
    var endTime: Double
    var thumbnail: UIImage?
    var volume: Double

    init(asset: AVAsset, startTime: Double = 0, endTime: Double? = nil, thumbnail: UIImage? = nil) {
        id = UUID()
        self.asset = asset
        self.startTime = startTime
        self.endTime = endTime ?? 0 // Will be set after loading duration
        self.thumbnail = thumbnail
        volume = 1.0
    }
}
