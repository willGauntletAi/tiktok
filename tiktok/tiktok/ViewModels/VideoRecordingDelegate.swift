import AVFoundation
import Foundation

class VideoRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinishRecording: ((URL, Error?) -> Void)?

    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from _: [AVCaptureConnection], error: Error?) {
        onFinishRecording?(outputFileURL, error)
    }

    func fileOutput(_: AVCaptureFileOutput, didStartRecordingTo _: URL, from _: [AVCaptureConnection]) {
        // Recording started successfully
    }
}
