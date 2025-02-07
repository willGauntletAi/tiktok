@preconcurrency import AVFoundation
@preconcurrency import CoreImage

protocol SendableAttributes: Sendable {
    var asDictionary: [String: Any] { get }
}

@objc final class VideoCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    // Custom Sendable wrapper for pixel buffer attributes
    private struct PixelBufferAttributes: @unchecked Sendable {
        private let storage: NSDictionary
        
        init(format: Int32, metalCompatible: Bool) {
            self.storage = [
                kCVPixelBufferPixelFormatTypeKey as String: format,
                kCVPixelBufferMetalCompatibilityKey as String: metalCompatible
            ]
        }
        
        var asDictionary: [String: Any] { storage as! [String: Any] }
    }
    
    private static let attributes = PixelBufferAttributes(
        format: Int32(kCVPixelFormatType_32BGRA),
        metalCompatible: true
    )
    
    // Actor to handle non-sendable state
    private actor RenderingActor {
        let context: CIContext
        
        init() {
            self.context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
        }
        
        func render(_ sourceImage: CIImage) -> CIImage {
            // Apply any additional processing here if needed
            return sourceImage
        }
    }
    
    private let renderingActor = RenderingActor()
    private let renderQueue = DispatchQueue(label: "com.app.videocompositor", qos: .userInteractive)
    private let renderContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    
    nonisolated func renderContextChanged(_: AVVideoCompositionRenderContext) {}
    
    nonisolated func cancelAllPendingVideoCompositionRequests() {}
    
    @objc nonisolated var sourcePixelBufferAttributes: [String: Any]? {
        Self.attributes.asDictionary
    }
    
    @objc nonisolated var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        Self.attributes.asDictionary
    }
    
    nonisolated func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // Capture values needed for processing
        let trackID = request.sourceTrackIDs[0].int32Value
        let renderingActor = self.renderingActor
        let context = self.renderContext
        
        Task {
            guard let sourceBuffer = request.sourceFrame(byTrackID: trackID),
                  let destinationBuffer = request.renderContext.newPixelBuffer()
            else {
                request.finish(with: NSError(domain: "VideoCompositor", code: -1, userInfo: nil))
                return
            }
            
            let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
            
            // Process the image using the isolated actor
            let processedImage = await renderingActor.render(sourceImage)
            
            // Render the result outside the actor since CVPixelBuffer is not Sendable
            context.render(processedImage, to: destinationBuffer)
            request.finish(withComposedVideoFrame: destinationBuffer)
        }
    }
}

// Extension to make dictionary values Sendable
fileprivate extension Dictionary where Value: Any {
    var withSendableValues: [Key: Any] {
        var result: [Key: Any] = [:]
        for (key, value) in self {
            switch value {
            case let number as NSNumber:
                result[key] = number.int64Value
            case let string as String:
                result[key] = string
            case let bool as Bool:
                result[key] = bool
            default:
                result[key] = value
            }
        }
        return result
    }
} 