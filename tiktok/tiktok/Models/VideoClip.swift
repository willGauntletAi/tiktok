import AVFoundation
import UIKit

struct VideoClip: Identifiable {
    let id: UUID
    let asset: AVAsset
    var startTime: Double // Position in composition
    var endTime: Double // Position in composition
    var thumbnail: UIImage?
    var volume: Double
    let assetStartTime: Double // Original time in asset
    var assetDuration: Double // Original duration in asset

    init(asset: AVAsset, startTime: Double = 0, endTime: Double? = nil, thumbnail: UIImage? = nil, assetStartTime: Double = 0, assetDuration: Double? = nil) {
        id = UUID()
        self.asset = asset
        self.startTime = startTime
        self.endTime = endTime ?? 0 // Will be set after loading duration
        self.thumbnail = thumbnail
        volume = 1.0
        self.assetStartTime = assetStartTime
        if let duration = assetDuration {
            self.assetDuration = duration
        } else {
            self.assetDuration = (endTime ?? 0) - startTime
        }
    }
}
