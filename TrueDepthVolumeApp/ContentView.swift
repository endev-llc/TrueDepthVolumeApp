//
//  ContentView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var volumeManager = VolumeButtonManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(session: cameraManager.session)
                .onAppear {
                    cameraManager.startSession()
                    volumeManager.setupVolumeMonitoring()
                }
                .onDisappear {
                    cameraManager.stopSession()
                    volumeManager.stopVolumeMonitoring()
                }
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Button(action: {
                    cameraManager.captureAndSaveDepthData()
                }) {
                    Text("Capture & Save Depth Data")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(15)
                }
                
                if cameraManager.isProcessing {
                    Text("Processing...")
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
                
                if let lastSavedFile = cameraManager.lastSavedFileName {
                    Text("Saved: \(lastSavedFile)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .background(Color.green.opacity(0.7))
                        .cornerRadius(10)
                }
            }
            .padding(.bottom, 50)
            
            // Hidden volume view for capturing volume button presses
            VolumeView()
        }
        .alert(isPresented: $cameraManager.showError) {
            Alert(
                title: Text("Error"),
                message: Text(cameraManager.errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $cameraManager.showShareSheet) {
            if let fileURL = cameraManager.fileToShare {
                ShareSheet(items: [fileURL])
            }
        }
        .onReceive(volumeManager.$volumePressed) { pressed in
            if pressed {
                cameraManager.captureAndSaveDepthData()
            }
        }
    }
}

// MARK: - Volume Button Manager
class VolumeButtonManager: NSObject, ObservableObject {
    @Published var volumePressed = false
    
    private var initialVolume: Float = 0.0
    private var volumeView: MPVolumeView?
    
    func setupVolumeMonitoring() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
        
        initialVolume = AVAudioSession.sharedInstance().outputVolume
        
        // Start monitoring volume changes
        AVAudioSession.sharedInstance().addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new, .old],
            context: nil
        )
    }
    
    func stopVolumeMonitoring() {
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            guard let change = change,
                  let newValue = change[.newKey] as? Float,
                  let oldValue = change[.oldKey] as? Float else { return }
            
            // Detect volume up button press (volume increase)
            if newValue > oldValue {
                DispatchQueue.main.async {
                    self.volumePressed = true
                    // Reset the flag after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.volumePressed = false
                    }
                }
                
                // Reset volume to previous level to prevent actual volume change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let volumeSlider = self.getVolumeSlider() {
                        volumeSlider.value = oldValue
                    }
                }
            }
        }
    }
    
    private func getVolumeSlider() -> UISlider? {
        let volumeView = MPVolumeView()
        for subview in volumeView.subviews {
            if let slider = subview as? UISlider {
                return slider
            }
        }
        return nil
    }
    
    deinit {
        stopVolumeMonitoring()
    }
}

// MARK: - Volume View (Hidden)
struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        return volumeView
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Camera Manager (Core Logic)
class CameraManager: NSObject, ObservableObject, AVCaptureDepthDataOutputDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.example.sessionQueue")
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let depthDataQueue = DispatchQueue(label: "com.example.depthQueue")

    @Published var showError = false
    @Published var isProcessing = false
    @Published var lastSavedFileName: String?
    @Published var showShareSheet = false
    
    var errorMessage = ""
    var fileToShare: URL?

    private var latestDepthData: AVDepthData?

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        sessionQueue.async {
            self.session.beginConfiguration()

            guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
                self.presentError("TrueDepth camera is not available on this device.")
                return
            }

            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(videoDeviceInput) {
                    self.session.addInput(videoDeviceInput)
                } else {
                    self.presentError("Could not add video device input.")
                    return
                }
            } catch {
                self.presentError("Could not create video device input: \(error)")
                return
            }

            if self.session.canAddOutput(self.depthDataOutput) {
                self.session.addOutput(self.depthDataOutput)
                self.depthDataOutput.isFilteringEnabled = true
                self.depthDataOutput.setDelegate(self, callbackQueue: self.depthDataQueue)
            } else {
                self.presentError("Could not add depth data output.")
                return
            }

            self.session.commitConfiguration()
        }
    }

    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func presentError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
            self.isProcessing = false
        }
    }

    // MARK: - Delegate and Capture Logic

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        self.latestDepthData = depthData
    }

    func captureAndSaveDepthData() {
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        self.depthDataQueue.async {
            guard let depthData = self.latestDepthData else {
                self.presentError("No depth data available to capture.")
                return
            }
            self.saveDepthDataToFile(depthData: depthData)
        }
    }

    private func saveDepthDataToFile(depthData: AVDepthData) {
        // Convert to depth data if it's disparity data
        let processedDepthData: AVDepthData
        let isDisparityData: Bool
        
        // Check if this is disparity data and convert if needed
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            isDisparityData = true
            // Convert disparity to depth using Apple's proper conversion
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert disparity to depth: \(error.localizedDescription)")
                return
            }
        } else {
            isDisparityData = false
            processedDepthData = depthData
        }
        
        let depthMap = processedDepthData.depthDataMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // Create filename with timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "depth_data_\(timestamp).csv"
        
        // Get Documents directory
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.presentError("Could not access Documents directory.")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            var csvContent = "x,y,depth_meters,depth_geometry\n"
            
            // Track min/max for statistics (valid numbers only)
            var minDepth: Float = Float.infinity
            var maxDepth: Float = -Float.infinity
            var validPixelCount = 0
            
            // Process all pixels
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
                    // Keep a processed version for geometric correction
                    var processedDepth = depthValue
                    if isDisparityData && depthValue > 0 {
                        // Apply the geometric correction logic
                        if depthValue < 1.0 {
                            processedDepth = 1.0 / depthValue
                        }
                    }
                    
                    // Store BOTH values: raw depth for accuracy, processed for geometry
                    csvContent += "\(x),\(y),\(String(format: "%.6f", depthValue)),\(String(format: "%.6f", processedDepth))\n"
                    
                    // Track min/max for valid numbers only (for statistics)
                    if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                        minDepth = min(minDepth, depthValue)
                        maxDepth = max(maxDepth, depthValue)
                        validPixelCount += 1
                    }
                }
            }
            
            // Write to file
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Save metadata
            let metadataFileName = "depth_metadata_\(timestamp).txt"
            let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
            let metadata = """
            Depth Data Capture Metadata
            ===========================
            Timestamp: \(Date())
            Width: \(width) pixels
            Height: \(height) pixels
            Total pixels: \(width * height)
            Valid pixels: \(validPixelCount)
            Coverage: \(String(format: "%.1f", Float(validPixelCount) / Float(width * height) * 100))%
            
            Original depth data type: \(depthData.depthDataType)
            Was disparity data: \(isDisparityData)
            Processed depth data type: \(processedDepthData.depthDataType)
            
            Depth Statistics (valid pixels only):
            Min depth: \(minDepth == Float.infinity ? "N/A" : String(format: "%.6f", minDepth))m
            Max depth: \(maxDepth == -Float.infinity ? "N/A" : String(format: "%.6f", maxDepth))m
            Range: \(minDepth == Float.infinity || maxDepth == -Float.infinity ? "N/A" : String(format: "%.6f", maxDepth - minDepth))m
            
            Camera calibration: \(String(describing: depthData.cameraCalibrationData))
            
            File: \(fileName)
            Location: \(fileURL.path)
            
            Notes:
            - Depth values are in meters (properly converted from disparity)
            - Closer objects have SMALLER depth values
            - Farther objects have LARGER depth values
            - Uses Apple's calibrated disparity-to-depth conversion
            """
            
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
            
            let validMinDepth = minDepth == Float.infinity ? 0 : minDepth
            let validMaxDepth = maxDepth == -Float.infinity ? 0 : maxDepth
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastSavedFileName = fileName
                self.fileToShare = fileURL
                self.showShareSheet = true
                
                print("✅ Depth data saved successfully!")
                print("📍 File location: \(fileURL.path)")
                print("📊 Dimensions: \(width) x \(height)")
                print("📊 Valid pixels: \(validPixelCount)/\(width * height)")
                print("📊 Depth range: \(String(format: "%.6f", validMinDepth))m - \(String(format: "%.6f", validMaxDepth))m")
                print("🔄 Was disparity data: \(isDisparityData)")
            }
            
        } catch {
            self.presentError("Failed to save depth data: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Utilities
struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.frame = view.bounds
        previewLayer.frame = view.layer.frame
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiView: UIActivityViewController, context: Context) {}
}
