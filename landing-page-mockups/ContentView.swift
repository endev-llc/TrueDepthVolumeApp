//
//  ContentView.swift
//  landing-page-mockups
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraView(session: cameraManager.session)
                .onAppear(perform: cameraManager.startSession)
                .onDisappear(perform: cameraManager.stopSession)
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
    }
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
        let depthMap = depthData.depthDataMap

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
            var csvContent = "x,y,depth_meters\n" // CSV header
            
            // Extract all depth values
            for y in 0..<height {
                for x in 0..<width {
                    let depth = floatBuffer[y * (bytesPerRow / MemoryLayout<Float32>.stride) + x]
                    
                    // Include all values, even NaN/infinite (they'll be marked in CSV)
                    let depthValue: String
                    if depth.isNaN {
                        depthValue = "NaN"
                    } else if depth.isInfinite {
                        depthValue = "Infinite"
                    } else {
                        depthValue = String(depth)
                    }
                    
                    csvContent += "\(x),\(y),\(depthValue)\n"
                }
            }
            
            // Write to file
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Also save metadata
            let metadataFileName = "depth_metadata_\(timestamp).txt"
            let metadataURL = documentsDirectory.appendingPathComponent(metadataFileName)
            let metadata = """
            Depth Data Capture Metadata
            ===========================
            Timestamp: \(Date())
            Width: \(width) pixels
            Height: \(height) pixels
            Total pixels: \(width * height)
            Depth data type: \(depthData.depthDataType)
            Camera calibration: \(depthData.cameraCalibrationData)
            
            File: \(fileName)
            Location: \(fileURL.path)
            """
            
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastSavedFileName = fileName
                self.fileToShare = fileURL
                self.showShareSheet = true
                
                print("✅ Depth data saved successfully!")
                print("📍 File location: \(fileURL.path)")
                print("📊 Dimensions: \(width) x \(height)")
                print("📁 You can find this file in the Files app under 'On My iPhone' > 'YourAppName'")
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
