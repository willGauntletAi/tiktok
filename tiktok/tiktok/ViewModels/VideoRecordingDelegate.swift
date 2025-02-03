import Foundation
import AVFoundation

class VideoRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinishRecording: ((URL, Error?) -> Void)?
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        onFinishRecording?(outputFileURL, error)
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Recording started successfully
    }
} 
