//
//  AccessibleReceiptCameraView.swift
//  Halo-fi-IOS
//
//  A camera a blind user can aim. AVFoundation preview + Vision rectangle
//  detection every few frames → spoken cues ("Move the phone left",
//  "Closer", "Hold still… captured"). Capture by:
//    - Magic Tap (two-finger double tap) anywhere — accessibilityPerformMagicTap
//    - the big Capture button
//    - auto-capture after the receipt has been steady and fully in frame
//  A capture haptic fires with the shutter so the user feels it.
//
//  This is the VoiceOver-time replacement for VisionKit's document scanner,
//  whose framing guidance is silent under VoiceOver (device test pending).
//

import AVFoundation
import SwiftUI
import UIKit
import Vision

struct AccessibleReceiptCameraView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> AccessibleReceiptCameraController {
        let vc = AccessibleReceiptCameraController()
        vc.completion = completion
        return vc
    }

    func updateUIViewController(_ uiViewController: AccessibleReceiptCameraController, context: Context) {}
}

final class AccessibleReceiptCameraController: UIViewController {
    var completion: ((UIImage?) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "halofi.receipt.camera")
    private let analysisQueue = DispatchQueue(label: "halofi.receipt.analysis")

    private var frameCounter = 0
    private var steadyFrames = 0
    private var lastCue = ""
    private var lastCueAt = Date.distantPast
    private var isCapturing = false
    private var didFinish = false

    private let captureButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let cueLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        checkPermissionAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Magic Tap = capture

    override func accessibilityPerformMagicTap() -> Bool {
        capture()
        return true
    }

    override func accessibilityPerformEscape() -> Bool {
        finish(with: nil)
        return true
    }

    // MARK: - UI

    private func setupUI() {
        cueLabel.text = "Point the camera at the receipt."
        cueLabel.textColor = .white
        cueLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        cueLabel.adjustsFontForContentSizeCategory = true
        cueLabel.numberOfLines = 0
        cueLabel.textAlignment = .center
        cueLabel.translatesAutoresizingMaskIntoConstraints = false
        cueLabel.isAccessibilityElement = true
        cueLabel.accessibilityTraits = .updatesFrequently

        var config = UIButton.Configuration.filled()
        config.title = "Capture"
        config.baseBackgroundColor = .systemBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 32, bottom: 20, trailing: 32)
        captureButton.configuration = config
        captureButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title2)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        captureButton.accessibilityLabel = "Capture receipt"
        captureButton.accessibilityHint = "Takes the photo now. You can also double-tap with two fingers anywhere."

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "Cancel"
        cancelConfig.baseForegroundColor = .white
        cancelButton.configuration = cancelConfig
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        view.addSubview(cueLabel)
        view.addSubview(captureButton)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            cueLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cueLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            cueLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -24),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            captureButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            captureButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        view.accessibilityElements = [cueLabel, captureButton, cancelButton]
    }

    @objc private func captureTapped() { capture() }
    @objc private func cancelTapped() { finish(with: nil) }

    // MARK: - Session

    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() } else { self?.deniedCamera() }
                }
            }
        default:
            deniedCamera()
        }
    }

    private func deniedCamera() {
        cueLabel.text = "Camera access is off. Allow it in Settings, or choose a photo instead."
        UIAccessibility.post(notification: .announcement, argument: cueLabel.text ?? "")
        captureButton.isEnabled = false
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.deniedCamera() }
                return
            }
            session.addInput(input)
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.view.bounds
                self.view.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
                self.speak("Camera ready. Hold the phone flat above the receipt. Double-tap with two fingers to capture.", force: true)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Cues

    private func speak(_ cue: String, force: Bool = false) {
        let now = Date()
        guard force || (cue != lastCue && now.timeIntervalSince(lastCueAt) > 1.6) || now.timeIntervalSince(lastCueAt) > 5 else { return }
        lastCue = cue
        lastCueAt = now
        cueLabel.text = cue
        UIAccessibility.post(notification: .announcement, argument: cue)
    }

    /// Where the detected rectangle is relative to the frame → one cue.
    func cue(for rect: CGRect?) -> (String, Bool) {
        guard let r = rect else { return ("I can't see the receipt yet. Move the phone slowly.", false) }
        let area = r.width * r.height
        if area < 0.18 { return ("Closer.", false) }
        if r.minX < 0.02 && r.maxX > 0.98 { return ("Too close. Move back a little.", false) }
        if r.minX < 0.04 { return ("Move the phone left a little.", false) }
        if r.maxX > 0.96 { return ("Move the phone right a little.", false) }
        if r.minY < 0.04 { return ("Move the phone down a little.", false) }
        if r.maxY > 0.96 { return ("Move the phone up a little.", false) }
        return ("Good. Hold still.", true)
    }

    // MARK: - Capture

    private func capture() {
        guard !isCapturing, session.isRunning else { return }
        isCapturing = true
        Haptics.engine.play(.tapCrisp)
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func finish(with image: UIImage?) {
        guard !didFinish else { return }
        didFinish = true
        completion?(image)
    }
}

// MARK: - Frame analysis

extension AccessibleReceiptCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        guard frameCounter % 8 == 0, !isCapturing, !didFinish,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            guard let self else { return }
            let best = (request.results as? [VNRectangleObservation])?
                .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            let box = best.map { obs -> CGRect in
                // Vision is bottom-left origin; flip Y for "up/down" cues.
                CGRect(x: obs.boundingBox.minX, y: 1 - obs.boundingBox.maxY,
                       width: obs.boundingBox.width, height: obs.boundingBox.height)
            }
            let (text, framed) = self.cue(for: box)
            DispatchQueue.main.async {
                self.speak(text)
                if framed {
                    self.steadyFrames += 1
                    if self.steadyFrames >= 3 { // ~1 s steady at 8-frame stride
                        self.steadyFrames = 0
                        self.capture()
                    }
                } else {
                    self.steadyFrames = 0
                }
            }
        }
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.2
        request.maximumObservations = 3
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:]).perform([request])
    }
}

extension AccessibleReceiptCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            speak("Couldn't take the photo. Try again.", force: true)
            return
        }
        Haptics.success()
        speak("Captured.", force: true)
        sessionQueue.async { [session] in session.stopRunning() }
        finish(with: image)
    }
}
