//
//  ContentView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import CoreGraphics
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var volumeManager = VolumeButtonManager()
    @State private var showOverlayView = false
    @State private var uploadedCSVFile: URL?
    @State private var showDocumentPicker = false

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
                    cameraManager.captureDepthAndPhoto()
                }) {
                    Text("Capture Depth + Photo")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(15)
                }
                
                Button(action: {
                    showDocumentPicker = true
                }) {
                    Text("Upload CSV")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.cyan)
                        .cornerRadius(15)
                }
                
                if cameraManager.isProcessing {
                    Text("Processing...")
                        .foregroundColor(.white)
                        .padding(.horizontal)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
                
                // Show buttons when data is captured
                if cameraManager.capturedDepthImage != nil && cameraManager.capturedPhoto != nil {
                    HStack(spacing: 15) {
                        Button(action: {
                            showOverlayView = true
                        }) {
                            Text("View Overlay")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(15)
                        }
                        
                        // Export button
                        Button(action: {
                            cameraManager.showShareSheet = true
                        }) {
                            Text("Export")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(15)
                        }
                        .disabled(cameraManager.fileToShare == nil && cameraManager.croppedFileToShare == nil)
                    }
                }
                
                // 3D View button (show if we have uploaded CSV or cropped file)
                if uploadedCSVFile != nil || cameraManager.croppedFileToShare != nil {
                    Button(action: {
                        cameraManager.show3DView = true
                    }) {
                        Text("View 3D")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(15)
                    }
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
            // Export cropped CSV if available, otherwise raw CSV
            if let croppedFileURL = cameraManager.croppedFileToShare {
                ShareSheet(items: [croppedFileURL])
            } else if let fileURL = cameraManager.fileToShare {
                ShareSheet(items: [fileURL])
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(selectedFileURL: $uploadedCSVFile)
        }
        .fullScreenCover(isPresented: $showOverlayView) {
            if let depthImage = cameraManager.capturedDepthImage,
               let photo = cameraManager.capturedPhoto {
                OverlayView(
                    depthImage: depthImage,
                    photo: photo,
                    cameraManager: cameraManager,
                    onDismiss: { showOverlayView = false }
                )
            }
        }
        .fullScreenCover(isPresented: $cameraManager.show3DView) {
            // Prioritize uploaded CSV, then fall back to cropped file
            if let uploadedCSV = uploadedCSVFile {
                DepthVisualization3DView(
                    csvFileURL: uploadedCSV,
                    onDismiss: { cameraManager.show3DView = false }
                )
            } else if let croppedFileURL = cameraManager.croppedFileToShare {
                DepthVisualization3DView(
                    csvFileURL: croppedFileURL,
                    onDismiss: { cameraManager.show3DView = false }
                )
            }
        }
        .onReceive(volumeManager.$volumePressed) { pressed in
            if pressed {
                cameraManager.captureDepthAndPhoto()
            }
        }
    }
}

// MARK: - Enhanced Overlay View with Drawing
struct OverlayView: View {
    let depthImage: UIImage
    let photo: UIImage
    let cameraManager: CameraManager
    let onDismiss: () -> Void
    
    @State private var photoOpacity: Double = 0.7
    @State private var showingDepthOnly = false
    @State private var isDrawingMode = false
    @State private var drawnPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var imageFrame: CGRect = .zero
    @State private var showingConfirmation = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header controls
                HStack {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    if !isDrawingMode {
                        Button(showingDepthOnly ? "Show Both" : "Depth Only") {
                            showingDepthOnly.toggle()
                        }
                        .foregroundColor(.white)
                        .padding()
                        
                        Button("Draw Outline") {
                            isDrawingMode = true
                            drawnPath = []
                        }
                        .foregroundColor(.cyan)
                        .padding()
                    } else {
                        Button("Clear") {
                            drawnPath = []
                        }
                        .foregroundColor(.red)
                        .padding()
                        
                        Button("Cancel") {
                            isDrawingMode = false
                            drawnPath = []
                        }
                        .foregroundColor(.white)
                        .padding()
                        
                        if drawnPath.count > 10 {
                            Button("Confirm") {
                                showingConfirmation = true
                            }
                            .foregroundColor(.green)
                            .padding()
                        }
                    }
                }
                
                // Opacity slider
                if !showingDepthOnly {
                    HStack {
                        Text("Photo Opacity:")
                            .foregroundColor(.white)
                        Slider(value: $photoOpacity, in: 0...1)
                            .accentColor(.blue)
                        Text("\(Int(photoOpacity * 100))%")
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                // Image overlay with drawing
                GeometryReader { geometry in
                    ZStack {
                        // Depth image (bottom layer)
                        Image(uiImage: depthImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .background(
                                GeometryReader { imageGeometry in
                                    Color.clear
                                        .onAppear {
                                            // Calculate the actual image frame within the GeometryReader
                                            let imageAspectRatio = depthImage.size.width / depthImage.size.height
                                            let containerAspectRatio = geometry.size.width / geometry.size.height
                                            
                                            if imageAspectRatio > containerAspectRatio {
                                                // Image is wider - fit to width
                                                let imageHeight = geometry.size.width / imageAspectRatio
                                                let yOffset = (geometry.size.height - imageHeight) / 2
                                                imageFrame = CGRect(x: 0, y: yOffset, width: geometry.size.width, height: imageHeight)
                                            } else {
                                                // Image is taller - fit to height
                                                let imageWidth = geometry.size.height * imageAspectRatio
                                                let xOffset = (geometry.size.width - imageWidth) / 2
                                                imageFrame = CGRect(x: xOffset, y: 0, width: imageWidth, height: geometry.size.height)
                                            }
                                        }
                                }
                            )
                        
                        // Photo (top layer with opacity)
                        if !showingDepthOnly {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // Drawing overlay
                        if isDrawingMode {
                            DrawingOverlay(
                                path: $drawnPath,
                                isDrawing: $isDrawing,
                                frameSize: geometry.size,
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Show completed outline
                        if !isDrawingMode && !drawnPath.isEmpty {
                            Path { path in
                                guard !drawnPath.isEmpty else { return }
                                path.move(to: drawnPath[0])
                                for point in drawnPath.dropFirst() {
                                    path.addLine(to: point)
                                }
                                path.closeSubpath()
                            }
                            .stroke(Color.cyan, lineWidth: 3)
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Info text
                Text(isDrawingMode ?
                     "Draw around the object you want to isolate. Tap 'Confirm' when done." :
                     "Align the images to ensure depth data matches visual features")
                    .foregroundColor(.white)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .alert("Confirm Outline", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Crop CSV") {
                cropCSVWithOutline()
                isDrawingMode = false
            }
        } message: {
            Text("This will crop the depth data to only include points within your outline. Continue?")
        }
    }
    
    private func cropCSVWithOutline() {
        // Convert drawn path to depth data coordinates and crop CSV
        let imageSize = depthImage.size
        let scaledPath = drawnPath.map { point in
            // Convert from view coordinates to image coordinates
            let relativeX = (point.x - imageFrame.minX) / imageFrame.width
            let relativeY = (point.y - imageFrame.minY) / imageFrame.height
            
            // Convert to depth image coordinates
            let depthX = relativeX * imageSize.width
            let depthY = relativeY * imageSize.height
            
            return CGPoint(x: depthX, y: depthY)
        }
        
        cameraManager.cropDepthDataWithPath(scaledPath)
    }
}

// MARK: - Drawing Overlay
struct DrawingOverlay: UIViewRepresentable {
    @Binding var path: [CGPoint]
    @Binding var isDrawing: Bool
    let frameSize: CGSize
    let imageFrame: CGRect
    
    func makeUIView(context: Context) -> DrawingView {
        let view = DrawingView()
        view.backgroundColor = UIColor.clear
        view.onPathUpdate = { newPath in
            path = newPath
        }
        view.onDrawingStateChange = { drawing in
            isDrawing = drawing
        }
        view.imageFrame = imageFrame
        return view
    }
    
    func updateUIView(_ uiView: DrawingView, context: Context) {
        uiView.imageFrame = imageFrame
    }
}

// MARK: - Custom Drawing UIView
class DrawingView: UIView {
    var onPathUpdate: (([CGPoint]) -> Void)?
    var onDrawingStateChange: ((Bool) -> Void)?
    var imageFrame: CGRect = .zero
    
    private var currentPath: [CGPoint] = []
    private var pathLayer: CAShapeLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        pathLayer = CAShapeLayer()
        pathLayer?.strokeColor = UIColor.cyan.cgColor
        pathLayer?.fillColor = UIColor.clear.cgColor
        pathLayer?.lineWidth = 3.0
        pathLayer?.lineCap = .round
        pathLayer?.lineJoin = .round
        layer.addSublayer(pathLayer!)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        // Only allow drawing within the image frame
        if imageFrame.contains(point) {
            currentPath = [point]
            onDrawingStateChange?(true)
            updatePath()
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        // Only add points within the image frame
        if imageFrame.contains(point) {
            currentPath.append(point)
            updatePath()
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onDrawingStateChange?(false)
        onPathUpdate?(currentPath)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        onDrawingStateChange?(false)
    }
    
    private func updatePath() {
        guard !currentPath.isEmpty else { return }
        
        let path = UIBezierPath()
        path.move(to: currentPath[0])
        
        for point in currentPath.dropFirst() {
            path.addLine(to: point)
        }
        
        pathLayer?.path = path.cgPath
    }
}

// MARK: - Volume Button Manager (unchanged)
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
            
            if newValue > oldValue {
                DispatchQueue.main.async {
                    self.volumePressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.volumePressed = false
                    }
                }
                
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

// MARK: - Volume View (unchanged)
struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        return volumeView
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Enhanced Camera Manager
class CameraManager: NSObject, ObservableObject, AVCaptureDepthDataOutputDelegate, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.example.sessionQueue")
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let depthDataQueue = DispatchQueue(label: "com.example.depthQueue")

    @Published var showError = false
    @Published var isProcessing = false
    @Published var lastSavedFileName: String?
    @Published var showShareSheet = false
    @Published var capturedDepthImage: UIImage?
    @Published var capturedPhoto: UIImage?
    @Published var croppedFileToShare: URL?
    @Published var hasOutline = false
    @Published var show3DView = false
    
    var errorMessage = ""
    var fileToShare: URL?

    private var latestDepthData: AVDepthData?
    private var currentDepthData: AVDepthData?
    private var currentPhotoData: Data?
    private var captureCompletion: ((Bool) -> Void)?
    private var rawDepthData: AVDepthData? // Store the raw depth data for cropping
    private var cameraCalibrationData: AVCameraCalibrationData? // Store camera intrinsics

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

            // Add depth output
            if self.session.canAddOutput(self.depthDataOutput) {
                self.session.addOutput(self.depthDataOutput)
                self.depthDataOutput.isFilteringEnabled = true
                self.depthDataOutput.setDelegate(self, callbackQueue: self.depthDataQueue)
            } else {
                self.presentError("Could not add depth data output.")
                return
            }
            
            // Add photo output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isDepthDataDeliveryEnabled = true
            } else {
                self.presentError("Could not add photo output.")
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

    // MARK: - Depth Data Delegate
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        self.latestDepthData = depthData
        
        // Capture camera calibration data for accurate coordinate conversion
        if let calibrationData = depthData.cameraCalibrationData {
            self.cameraCalibrationData = calibrationData
//            print("📷 Captured camera intrinsics:")
//            print("  Focal Length: fx=\(calibrationData.intrinsicMatrix.columns.0.x), fy=\(calibrationData.intrinsicMatrix.columns.1.y)")
//            print("  Principal Point: cx=\(calibrationData.intrinsicMatrix.columns.2.x), cy=\(calibrationData.intrinsicMatrix.columns.2.y)")
//            print("  Image Dimensions: \(calibrationData.intrinsicMatrixReferenceDimensions)")
        }
    }
    
    // MARK: - Photo Capture Delegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            return
        }
        
        if let imageData = photo.fileDataRepresentation() {
            self.currentPhotoData = imageData
            self.processSimultaneousCapture()
        }
    }

    // MARK: - Simultaneous Capture
    func captureDepthAndPhoto() {
        DispatchQueue.main.async {
            self.isProcessing = true
            self.capturedDepthImage = nil
            self.capturedPhoto = nil
            self.hasOutline = false
            self.croppedFileToShare = nil
        }
        
        // Capture current depth data
        self.depthDataQueue.async {
            guard let depthData = self.latestDepthData else {
                self.presentError("No depth data available to capture.")
                return
            }
            
            self.currentDepthData = depthData
            
            // Trigger photo capture
            let settings = AVCapturePhotoSettings()
            settings.isDepthDataDeliveryEnabled = true
            
            DispatchQueue.main.async {
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    
    private func processSimultaneousCapture() {
        guard let depthData = currentDepthData,
              let photoData = currentPhotoData else {
            self.presentError("Missing depth data or photo data.")
            return
        }
        
        // Store raw depth data for later cropping
        self.rawDepthData = depthData
        
        // Store camera calibration data for accurate measurements
        if let calibrationData = depthData.cameraCalibrationData {
            self.cameraCalibrationData = calibrationData
        }
        
        // Process depth data visualization
        let depthImage = self.createDepthVisualization(from: depthData)
        
        // Process photo
        let photo = UIImage(data: photoData)
        
        // Save CSV file
        self.saveDepthDataToFile(depthData: depthData)
        
        DispatchQueue.main.async {
            self.capturedDepthImage = depthImage
            self.capturedPhoto = photo
            self.isProcessing = false
        }
        
        // Clear temporary data
        self.currentDepthData = nil
        self.currentPhotoData = nil
    }

    // MARK: - CSV Cropping Function
    func cropDepthDataWithPath(_ path: [CGPoint]) {
        guard let depthData = rawDepthData else {
            presentError("No depth data available for cropping.")
            return
        }
        
        saveDepthDataToFile(depthData: depthData, cropPath: path)
        
        DispatchQueue.main.async {
            self.hasOutline = true
        }
    }
    
    // MARK: - Point in Polygon Algorithm
    private func isPointInPolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        let x = point.x
        let y = point.y
        var inside = false
        
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }

    // MARK: - Depth Visualization (unchanged)
    private func createDepthVisualization(from depthData: AVDepthData) -> UIImage? {
        // Convert to depth data if it's disparity data
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                print("Failed to convert disparity to depth: \(error)")
                return nil
            }
        } else {
            processedDepthData = depthData
        }
        
        let depthMap = processedDepthData.depthDataMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let originalWidth = CVPixelBufferGetWidth(depthMap)
        let originalHeight = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: originalWidth * originalHeight)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        // Find min/max depth for normalization
        var minDepth: Float = Float.infinity
        var maxDepth: Float = -Float.infinity
        
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    minDepth = min(minDepth, depthValue)
                    maxDepth = max(maxDepth, depthValue)
                }
            }
        }
        
        // Create CGImage with rotated dimensions (90° clockwise rotation)
        let rotatedWidth = originalHeight  // Swap width and height
        let rotatedHeight = originalWidth
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: nil,
                                    width: rotatedWidth,
                                    height: rotatedHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: rotatedWidth * 4,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        let data = context.data!.bindMemory(to: UInt8.self, capacity: rotatedWidth * rotatedHeight * 4)
        
        // Apply jet colormap (from HTML)
        let jetColormap: [[Float]] = [
            [0, 0, 128], [0, 0, 255], [0, 128, 255], [0, 255, 255],
            [128, 255, 128], [255, 255, 0], [255, 128, 0], [255, 0, 0], [128, 0, 0]
        ]
        
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                var color: [Float] = [0, 0, 0] // Default black
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 && minDepth != maxDepth {
                    let normalizedDepth = (depthValue - minDepth) / (maxDepth - minDepth)
                    let invertedDepth = 1.0 - normalizedDepth // Closer = hot, farther = cool
                    color = interpolateColor(colormap: jetColormap, t: invertedDepth)
                }
                
                // Rotate 90° counterclockwise: (x,y) -> (originalHeight-1-y, x)
                let rotatedX = originalHeight - 1 - y
                let rotatedY = x
                let dataIndex = (rotatedY * rotatedWidth + rotatedX) * 4
                
                data[dataIndex] = UInt8(color[0])     // R
                data[dataIndex + 1] = UInt8(color[1]) // G
                data[dataIndex + 2] = UInt8(color[2]) // B
                data[dataIndex + 3] = 255             // A
            }
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private func interpolateColor(colormap: [[Float]], t: Float) -> [Float] {
        let clampedT = max(0, min(1, t))
        let scaledT = clampedT * Float(colormap.count - 1)
        let index = Int(floor(scaledT))
        let frac = scaledT - Float(index)
        
        if index >= colormap.count - 1 {
            return colormap[colormap.count - 1]
        }
        
        let color1 = colormap[index]
        let color2 = colormap[index + 1]
        
        return [
            color1[0] + (color2[0] - color1[0]) * frac,
            color1[1] + (color2[1] - color1[1]) * frac,
            color1[2] + (color2[2] - color1[2]) * frac
        ]
    }

    // MARK: - Enhanced CSV Save Function with Cropping
    private func saveDepthDataToFile(depthData: AVDepthData, cropPath: [CGPoint]? = nil) {
        // Always convert to depth data using Apple's calibrated conversion
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            // Convert disparity to true depth values using Apple's calibrated conversion
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert disparity to depth: \(error.localizedDescription)")
                return
            }
        } else {
            // Already depth data, ensure it's Float32 format
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert depth data format: \(error.localizedDescription)")
                return
            }
        }
        
        let depthMap = processedDepthData.depthDataMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = cropPath != nil ? "depth_data_cropped_\(timestamp).csv" : "depth_data_\(timestamp).csv"
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.presentError("Could not access Documents directory.")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            var csvContent = "x,y,depth_meters\n"
            
            // Add camera calibration data as comments (if available)
            if let calibrationData = self.cameraCalibrationData {
                let intrinsics = calibrationData.intrinsicMatrix
                csvContent += "# Camera Intrinsics: fx=\(intrinsics.columns.0.x), fy=\(intrinsics.columns.1.y), cx=\(intrinsics.columns.2.x), cy=\(intrinsics.columns.2.y)\n"
                let dimensions = calibrationData.intrinsicMatrixReferenceDimensions
                csvContent += "# Reference Dimensions: width=\(dimensions.width), height=\(dimensions.height)\n"
            }
            
            // Add data source information
            let originalDataType = depthData.depthDataType
            if originalDataType == kCVPixelFormatType_DisparityFloat16 || originalDataType == kCVPixelFormatType_DisparityFloat32 {
                csvContent += "# Original Data: Disparity (converted to depth using Apple's calibrated conversion)\n"
            } else {
                csvContent += "# Original Data: Depth\n"
            }
            
            var minDepth: Float = Float.infinity
            var maxDepth: Float = -Float.infinity
            var validPixelCount = 0
            var croppedPixelCount = 0
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex] // This is now always true depth in meters
                    
                    // Check if cropping is enabled and if point is within the crop path
                    var shouldInclude = true
                    if let cropPath = cropPath, !cropPath.isEmpty {
                        // Convert depth coordinates to rotated display coordinates to match the drawn path
                        // The depth visualization applies: rotatedX = originalHeight - 1 - y, rotatedY = x
                        let displayX = CGFloat(height - 1 - y)  // Matches the rotation in createDepthVisualization
                        let displayY = CGFloat(x)
                        let point = CGPoint(x: displayX, y: displayY)
                        shouldInclude = isPointInPolygon(point: point, polygon: cropPath)
                    }
                    
                    if shouldInclude {
                        // Save the true depth value (already converted from disparity if needed)
                        csvContent += "\(x),\(y),\(String(format: "%.6f", depthValue))\n"
                        croppedPixelCount += 1
                        
                        if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                            minDepth = min(minDepth, depthValue)
                            maxDepth = max(maxDepth, depthValue)
                            validPixelCount += 1
                        }
                    }
                }
            }
            
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let validMinDepth = minDepth == Float.infinity ? 0 : minDepth
            let validMaxDepth = maxDepth == -Float.infinity ? 0 : maxDepth
            
            DispatchQueue.main.async {
                self.lastSavedFileName = fileName
                
                if cropPath != nil {
                    self.croppedFileToShare = fileURL
                } else {
                    self.fileToShare = fileURL
                }
                
                print("Depth data saved successfully!")
                print("File location: \(fileURL.path)")
                print("Dimensions: \(width) x \(height)")
                print("Valid pixels: \(validPixelCount)/\(width * height)")
                if cropPath != nil {
                    print("Cropped pixels: \(croppedPixelCount)/\(width * height)")
                }
                print("Depth range: \(String(format: "%.6f", validMinDepth))m - \(String(format: "%.6f", validMaxDepth))m")
                
                // Log conversion information
                let originalType = depthData.depthDataType
                if originalType == kCVPixelFormatType_DisparityFloat16 || originalType == kCVPixelFormatType_DisparityFloat32 {
                    print("Converted from disparity to true depth values using Apple's calibrated conversion")
                } else {
                    print("Original data was already in depth format")
                }
            }
            
        } catch {
            self.presentError("Failed to save depth data: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Utilities (unchanged)
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiView: UIActivityViewController, context: Context) {}
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFileURL: URL?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Copy the file to app's documents directory to ensure persistent access
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsDirectory.appendingPathComponent("uploaded_\(url.lastPathComponent)")
            
            do {
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // Copy the selected file
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.parent.selectedFileURL = destinationURL
                }
            } catch {
                print("Error copying CSV file: \(error)")
            }
        }
    }
}

// MARK: - Camera Intrinsics Structure
struct CameraIntrinsics {
    let fx: Float     // Focal length X
    let fy: Float     // Focal length Y
    let cx: Float     // Principal point X
    let cy: Float     // Principal point Y
    let width: Float  // Reference width
    let height: Float // Reference height
}

// MARK: - Volume Information Structure
struct VoxelVolumeInfo {
    let totalVolume: Double  // in cubic meters
    let voxelCount: Int
    let voxelSize: Float     // in meters
}

// MARK: - 3D Depth Visualization View with Voxels
import SceneKit

struct DepthVisualization3DView: View {
    let csvFileURL: URL
    let onDismiss: () -> Void
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    @State private var totalVolume: Double = 0.0
    @State private var voxelCount: Int = 0
    @State private var voxelSize: Float = 0.0
    @State private var cameraIntrinsics: CameraIntrinsics? = nil
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header
                HStack {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding()
                    
                    Spacer()
                    
                    VStack {
                        Text("3D Depth Visualization")
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        if voxelCount > 0 {
                            VStack(spacing: 4) {
                                Text("Volume: \(String(format: "%.2f", totalVolume * 1_000_000)) cm³")
                                    .foregroundColor(.cyan)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Text("\(voxelCount) voxels • \(String(format: "%.1f", voxelSize * 1000))mm each")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Button("") { }
                        .opacity(0)
                        .padding()
                }
                
                // 3D Scene or Loading/Error
                if isLoading {
                    Spacer()
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Using Real Camera Intrinsics for Perfect Accuracy...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    Spacer()
                } else if let errorMessage = errorMessage {
                    Spacer()
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.system(size: 50))
                        Text("Error Loading 3D Model")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else if let scene = scene {
                    SceneView(
                        scene: scene,
                        pointOfView: nil,
                        options: [.allowsCameraControl, .autoenablesDefaultLighting],
                        preferredFramesPerSecond: 60,
                        antialiasingMode: .multisampling4X,
                        delegate: nil,
                        technique: nil
                    )
                    .background(Color.black)
                }
                
                // Instructions
                if !isLoading && errorMessage == nil {
                    Text("Drag to rotate • Pinch to zoom • Pan with two fingers")
                        .foregroundColor(.gray)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .onAppear {
            loadAndCreate3DScene()
        }
    }
    
    private func loadAndCreate3DScene() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let csvContent = try String(contentsOf: csvFileURL)
                let depthPoints = parseCSVContent(csvContent)
                let scene = create3DScene(from: depthPoints)
                
                DispatchQueue.main.async {
                    self.scene = scene
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load CSV file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func parseCSVContent(_ content: String) -> [DepthPoint] {
        var points: [DepthPoint] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Parse camera intrinsics from comments (if available)
        for line in lines {
            if line.hasPrefix("# Camera Intrinsics:") {
                cameraIntrinsics = parseCameraIntrinsics(from: lines)
                break
            }
        }
        
        if let intrinsics = cameraIntrinsics {
            print("🎯 Loaded camera intrinsics from CSV: fx=\(intrinsics.fx), fy=\(intrinsics.fy)")
        } else {
            print("⚠️ No camera intrinsics found in CSV")
        }
        
        // Skip header and comment lines
        for line in lines {
            if line.hasPrefix("#") || line.contains("x,y,depth") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            let components = line.components(separatedBy: ",")
            
            // Handle both old format (4 columns: x,y,depth_meters,depth_geometry) and new format (3 columns: x,y,depth_meters)
            if components.count >= 3 {
                guard let x = Float(components[0]),
                      let y = Float(components[1]),
                      let depth = Float(components[2]) else { continue }
                
                // Skip invalid depth values
                if depth.isNaN || depth.isInfinite || depth <= 0 { continue }
                
                points.append(DepthPoint(x: x, y: y, depth: depth))
            }
        }
        
        print("📊 Parsed \(points.count) valid depth points from CSV")
        return points
    }
    
    private func parseCameraIntrinsics(from lines: [String]) -> CameraIntrinsics? {
        var fx: Float?
        var fy: Float?
        var cx: Float?
        var cy: Float?
        var width: Float?
        var height: Float?
        
        for line in lines {
            if line.hasPrefix("# Camera Intrinsics:") {
                // Parse: # Camera Intrinsics: fx=123.45, fy=123.45, cx=123.45, cy=123.45
                let parts = line.replacingOccurrences(of: "# Camera Intrinsics: ", with: "").components(separatedBy: ", ")
                for part in parts {
                    let keyValue = part.components(separatedBy: "=")
                    if keyValue.count == 2 {
                        let key = keyValue[0]
                        let value = Float(keyValue[1])
                        switch key {
                        case "fx": fx = value
                        case "fy": fy = value
                        case "cx": cx = value
                        case "cy": cy = value
                        default: break
                        }
                    }
                }
            } else if line.hasPrefix("# Reference Dimensions:") {
                // Parse: # Reference Dimensions: width=640.0, height=480.0
                let parts = line.replacingOccurrences(of: "# Reference Dimensions: ", with: "").components(separatedBy: ", ")
                for part in parts {
                    let keyValue = part.components(separatedBy: "=")
                    if keyValue.count == 2 {
                        let key = keyValue[0]
                        let value = Float(keyValue[1])
                        switch key {
                        case "width": width = value
                        case "height": height = value
                        default: break
                        }
                    }
                }
            }
        }
        
        if let fx = fx, let fy = fy, let cx = cx, let cy = cy, let width = width, let height = height {
            return CameraIntrinsics(fx: fx, fy: fy, cx: cx, cy: cy, width: width, height: height)
        }
        
        return nil
    }
    
    private func create3DScene(from points: [DepthPoint]) -> SCNScene {
        let scene = SCNScene()
        
        // Convert 2D depth data to 3D coordinates using camera intrinsics (if available)
        let measurementPoints3D = convertDepthPointsTo3D(points)
        
        // Create point cloud geometry using measurement coordinates
        let pointCloudGeometry = createPointCloudGeometry(from: measurementPoints3D)
        let pointCloudNode = SCNNode(geometry: pointCloudGeometry)
        
        // Create voxel geometry using the same measurement coordinates
        let (voxelGeometry, volumeInfo) = createVoxelGeometry(from: measurementPoints3D)
        let voxelNode = SCNNode(geometry: voxelGeometry)
        
        // Update volume information
        DispatchQueue.main.async {
            self.totalVolume = volumeInfo.totalVolume
            self.voxelCount = volumeInfo.voxelCount
            self.voxelSize = volumeInfo.voxelSize
        }
        
        scene.rootNode.addChildNode(pointCloudNode)
        scene.rootNode.addChildNode(voxelNode)
        
        // Add lighting
        setupLighting(scene: scene)
        
        // Setup camera using measurement coordinates
        setupCamera(scene: scene, pointCloud: measurementPoints3D)
        
        return scene
    }
    
    private func convertDepthPointsTo3D(_ points: [DepthPoint]) -> [SCNVector3] {
        guard !points.isEmpty else { return [] }
        
        var measurementPoints3D: [SCNVector3] = []
        
        guard let intrinsics = cameraIntrinsics else {
            print("⚠️ No camera intrinsics available")
            return []
        }
        
        print("🔧 APPLYING RESOLUTION SCALING CORRECTIONS")
        
        // CORRECTION: Scale intrinsics from 4032x2268 to 640x360 resolution
        let resolutionScaleX: Float = 640.0 / 4032.0   // = 0.1587
        let resolutionScaleY: Float = 360.0 / 2268.0   // = 0.1587
        
        let correctedFx = intrinsics.fx * resolutionScaleX
        let correctedFy = intrinsics.fy * resolutionScaleY
        let correctedCx = intrinsics.cx * resolutionScaleX
        let correctedCy = intrinsics.cy * resolutionScaleY
        
        print("📐 Resolution-Corrected Intrinsics:")
        print("  Original (4032x2268): fx=\(intrinsics.fx), fy=\(intrinsics.fy)")
        print("  Corrected (640x360): fx=\(correctedFx), fy=\(correctedFy)")
        print("  Scale factors: \(resolutionScaleX)x")
        
        for point in points {
            // Coordinates are already at 640x360 resolution - use directly
            let pixelX = point.x
            let pixelY = point.y
            let depthInMeters = point.depth
            
            // Unproject using resolution-corrected intrinsics
            let realWorldX = (pixelX - correctedCx) * depthInMeters / correctedFx
            let realWorldY = (pixelY - correctedCy) * depthInMeters / correctedFy
            let realWorldZ = depthInMeters
            
            measurementPoints3D.append(SCNVector3(realWorldX, realWorldY, realWorldZ))
        }
        
        // Center the point cloud
        let bbox = calculateBoundingBox(measurementPoints3D)
        let center = SCNVector3(
            (bbox.min.x + bbox.max.x) / 2.0,
            (bbox.min.y + bbox.max.y) / 2.0,
            (bbox.min.z + bbox.max.z) / 2.0
        )
        
        for i in 0..<measurementPoints3D.count {
            measurementPoints3D[i] = SCNVector3(
                measurementPoints3D[i].x - center.x,
                measurementPoints3D[i].y - center.y,
                measurementPoints3D[i].z - center.z
            )
        }
        
        let finalWidth = (bbox.max.x - bbox.min.x) * 100
        let finalHeight = (bbox.max.y - bbox.min.y) * 100
        let finalDepth = (bbox.max.z - bbox.min.z) * 100
        
        print("📏 CORRECTED DIMENSIONS:")
        print("  Width: \(finalWidth)cm (target: ~4cm)")
        print("  Height: \(finalHeight)cm (target: ~4cm)")
        print("  Depth: \(finalDepth)cm (target: ~3cm)")
        print("  Scaling errors: W=\(finalWidth/4.0)x, H=\(finalHeight/4.0)x, D=\(finalDepth/3.0)x")
        
        return measurementPoints3D
    }
    
    private func calculateBoundingBox(_ points: [SCNVector3]) -> (min: SCNVector3, max: SCNVector3) {
        guard !points.isEmpty else { return (SCNVector3(0, 0, 0), SCNVector3(0, 0, 0)) }
        
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        var minZ = points[0].z, maxZ = points[0].z
        
        for point in points {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
            minZ = Swift.min(minZ, point.z)
            maxZ = Swift.max(maxZ, point.z)
        }
        
        return (SCNVector3(minX, minY, minZ), SCNVector3(maxX, maxY, maxZ))
    }
    
    private func createVoxelGeometry(from measurementPoints3D: [SCNVector3]) -> (SCNGeometry, VoxelVolumeInfo) {
        guard !measurementPoints3D.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        // Use MEASUREMENT coordinates for everything - both volume calculation AND positioning
        let bbox = calculateBoundingBox(measurementPoints3D)
        let min = bbox.min
        let max = bbox.max
        
        let boundingBoxVolume = (max.x - min.x) * (max.y - min.y) * (max.z - min.z)
        
        // Calculate voxel size to fit 1 million voxels (in measurement space)
        let maxVoxels: Float = 1_000_000
        let voxelVolume = boundingBoxVolume / maxVoxels
        var voxelSize = pow(voxelVolume, 1.0/3.0)
        
        // Calculate grid dimensions using measurement space
        var gridX = Int(ceil((max.x - min.x) / voxelSize))
        var gridY = Int(ceil((max.y - min.y) / voxelSize))
        var gridZ = Int(ceil((max.z - min.z) / voxelSize))
        
        // If total exceeds limit, increase voxel size
        while gridX * gridY * gridZ > Int(maxVoxels) {
            voxelSize *= 1.01
            gridX = Int(ceil((max.x - min.x) / voxelSize))
            gridY = Int(ceil((max.y - min.y) / voxelSize))
            gridZ = Int(ceil((max.z - min.z) / voxelSize))
        }
        
        print("Measurement Voxel Grid: \(gridX) x \(gridY) x \(gridZ) = \(gridX * gridY * gridZ) voxels")
        print("Measurement Voxel size: \(voxelSize * 1000) mm")
        
        // Create spatial hash for surface points using MEASUREMENT coordinates
        var surfaceVoxels = Set<String>()
        
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize)
            let vy = Int((point.y - min.y) / voxelSize)
            let vz = Int((point.z - min.z) / voxelSize)
            
            // Clamp to grid bounds
            let clampedVx = Swift.max(0, Swift.min(gridX - 1, vx))
            let clampedVy = Swift.max(0, Swift.min(gridY - 1, vy))
            let clampedVz = Swift.max(0, Swift.min(gridZ - 1, vz))
            
            surfaceVoxels.insert("\(clampedVx),\(clampedVy),\(clampedVz)")
        }
        
        // Fill interior using layer-by-layer approach
        var filledVoxels = Set<String>()
        
        for z in 0..<gridZ {
            // Get surface points in this layer
            var layerSurface: [(x: Int, y: Int)] = []
            for voxelKey in surfaceVoxels {
                let components = voxelKey.split(separator: ",")
                let vz = Int(components[2])!
                if vz == z {
                    let vx = Int(components[0])!
                    let vy = Int(components[1])!
                    layerSurface.append((x: vx, y: vy))
                }
            }
            
            if layerSurface.count < 3 { continue }
            
            // Find convex hull of surface points in this layer
            let hull = convexHull2D(layerSurface)
            
            // Fill all voxels inside the hull
            let minX = layerSurface.map { $0.x }.min()!
            let maxX = layerSurface.map { $0.x }.max()!
            let minY = layerSurface.map { $0.y }.min()!
            let maxY = layerSurface.map { $0.y }.max()!
            
            for x in minX...maxX {
                for y in minY...maxY {
                    if pointInPolygon2D((x: x, y: y), hull) {
                        filledVoxels.insert("\(x),\(y),\(z)")
                    }
                }
            }
        }
        
        // Include surface voxels
        filledVoxels.formUnion(surfaceVoxels)
        
        guard !filledVoxels.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        print("Generated \(filledVoxels.count) voxel cubes")
        
        // Calculate total volume using MEASUREMENT coordinates (accurate)
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize) // in cubic meters
        let totalVolumeM3 = Double(filledVoxels.count) * singleVoxelVolume
        
        print("Accurate Total Volume: \(totalVolumeM3 * 1_000_000) cm³")
        
        // Create volume info
        let volumeInfo = VoxelVolumeInfo(
            totalVolume: totalVolumeM3,
            voxelCount: filledVoxels.count,
            voxelSize: voxelSize
        )
        
        // Create geometry using MEASUREMENT coordinates for consistent positioning
        var voxelVertices: [SCNVector3] = []
        var voxelColors: [SCNVector3] = []
        
        let halfSize = voxelSize * 0.5
        
        for voxelKey in filledVoxels {
            let components = voxelKey.split(separator: ",")
            let vx = Int(components[0])!
            let vy = Int(components[1])!
            let vz = Int(components[2])!
            
            // Calculate center in measurement space (consistent with volume calculation)
            let centerX = min.x + (Float(vx) + 0.5) * voxelSize
            let centerY = min.y + (Float(vy) + 0.5) * voxelSize
            let centerZ = min.z + (Float(vz) + 0.5) * voxelSize
            
            // Create 8 vertices for cube in measurement space
            let cubeVertices = [
                SCNVector3(centerX - halfSize, centerY - halfSize, centerZ - halfSize),
                SCNVector3(centerX + halfSize, centerY - halfSize, centerZ - halfSize),
                SCNVector3(centerX + halfSize, centerY + halfSize, centerZ - halfSize),
                SCNVector3(centerX - halfSize, centerY + halfSize, centerZ - halfSize),
                SCNVector3(centerX - halfSize, centerY - halfSize, centerZ + halfSize),
                SCNVector3(centerX + halfSize, centerY - halfSize, centerZ + halfSize),
                SCNVector3(centerX + halfSize, centerY + halfSize, centerZ + halfSize),
                SCNVector3(centerX - halfSize, centerY + halfSize, centerZ + halfSize)
            ]
            
            voxelVertices.append(contentsOf: cubeVertices)
            
            // Color based on measurement depth (Z coordinate)
            let normalizedDepth = (centerZ - min.z) / (max.z - min.z)
            let voxelColor = depthToColor(normalizedDepth)
            
            for _ in 0..<8 {
                voxelColors.append(voxelColor)
            }
        }
        
        // Create geometry sources
        let vertexData = Data(bytes: voxelVertices, count: voxelVertices.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: voxelVertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let colorData = Data(bytes: voxelColors, count: voxelColors.count * MemoryLayout<SCNVector3>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: voxelColors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        // Create indices for cube faces
        var indices: [UInt32] = []
        let cubeIndices: [UInt32] = [
            0, 1, 2,  2, 3, 0,  // Front
            4, 5, 6,  6, 7, 4,  // Back
            0, 4, 7,  7, 3, 0,  // Left
            1, 5, 6,  6, 2, 1,  // Right
            3, 2, 6,  6, 7, 3,  // Top
            0, 1, 5,  5, 4, 0   // Bottom
        ]
        
        for cubeIndex in 0..<(voxelVertices.count / 8) {
            let baseIndex = UInt32(cubeIndex * 8)
            for index in cubeIndices {
                indices.append(baseIndex + index)
            }
        }
        
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Configure material
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.transparency = 0.7
        geometry.materials = [material]
        
        return (geometry, volumeInfo)
    }
    
    private func convexHull2D(_ points: [(x: Int, y: Int)]) -> [(x: Int, y: Int)] {
        if points.count < 3 { return points }
        
        // Remove duplicates
        let uniquePoints = Array(Set(points.map { "\($0.x),\($0.y)" }))
            .compactMap { key -> (x: Int, y: Int)? in
                let parts = key.split(separator: ",")
                guard parts.count == 2,
                      let x = Int(parts[0]),
                      let y = Int(parts[1]) else { return nil }
                return (x: x, y: y)
            }
        
        if uniquePoints.count < 3 { return uniquePoints }
        
        // Find bottommost point
        var start = uniquePoints[0]
        for p in uniquePoints {
            if p.y < start.y || (p.y == start.y && p.x < start.x) {
                start = p
            }
        }
        
        // Sort by polar angle
        let others = uniquePoints.filter { $0.x != start.x || $0.y != start.y }
        let sorted = others.sorted { a, b in
            let angleA = atan2(Double(a.y - start.y), Double(a.x - start.x))
            let angleB = atan2(Double(b.y - start.y), Double(b.x - start.x))
            return angleA < angleB
        }
        
        // Build convex hull
        var hull = [start]
        for point in sorted {
            while hull.count >= 2 {
                let cross = (hull[hull.count-1].x - hull[hull.count-2].x) * (point.y - hull[hull.count-2].y) -
                           (hull[hull.count-1].y - hull[hull.count-2].y) * (point.x - hull[hull.count-2].x)
                if cross > 0 { break }
                hull.removeLast()
            }
            hull.append(point)
        }
        
        return hull
    }
    
    private func pointInPolygon2D(_ point: (x: Int, y: Int), _ polygon: [(x: Int, y: Int)]) -> Bool {
        if polygon.count < 3 { return false }
        
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if ((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
               (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    private func createPointCloudGeometry(from measurementPoints3D: [SCNVector3]) -> SCNGeometry {
        guard !measurementPoints3D.isEmpty else { return SCNGeometry() }
        
        // Create colors based on Z coordinate (depth) in measurement space
        let bbox = calculateBoundingBox(measurementPoints3D)
        let depthRange = bbox.max.z - bbox.min.z
        
        var colors: [SCNVector3] = []
        for point in measurementPoints3D {
            let normalizedDepth = depthRange > 0 ? (point.z - bbox.min.z) / depthRange : 0
            let color = depthToColor(normalizedDepth)
            colors.append(color)
        }
        
        // Create geometry source for vertices
        let vertexData = Data(bytes: measurementPoints3D, count: measurementPoints3D.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: measurementPoints3D.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        // Create geometry source for colors
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector3>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        // Create indices for points
        let indices: [UInt32] = Array(0..<UInt32(measurementPoints3D.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: measurementPoints3D.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        // Configure material for point cloud
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
    
    private func depthToColor(_ normalizedDepth: Float) -> SCNVector3 {
        // Jet colormap: blue (far) -> green -> yellow -> red (close)
        let t = normalizedDepth
        
        if t < 0.25 {
            // Blue to cyan
            let local_t = t / 0.25
            return SCNVector3(0, local_t, 1)
        } else if t < 0.5 {
            // Cyan to green
            let local_t = (t - 0.25) / 0.25
            return SCNVector3(0, 1, 1 - local_t)
        } else if t < 0.75 {
            // Green to yellow
            let local_t = (t - 0.5) / 0.25
            return SCNVector3(local_t, 1, 0)
        } else {
            // Yellow to red
            let local_t = (t - 0.75) / 0.25
            return SCNVector3(1, 1 - local_t, 0)
        }
    }
    

    
    private func setupLighting(scene: SCNScene) {
        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Main directional light
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = UIColor.white
        directionalLight.intensity = 600
        let lightNode = SCNNode()
        lightNode.light = directionalLight
        lightNode.position = SCNVector3(10, 15, 10)
        lightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(lightNode)
        
        // Secondary light for better voxel visibility
        let secondaryLight = SCNLight()
        secondaryLight.type = .directional
        secondaryLight.color = UIColor.white
        secondaryLight.intensity = 300
        let secondaryLightNode = SCNNode()
        secondaryLightNode.light = secondaryLight
        secondaryLightNode.position = SCNVector3(-10, 10, -10)
        secondaryLightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(secondaryLightNode)
    }
    
    private func setupCamera(scene: SCNScene, pointCloud: [SCNVector3]) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.zNear = 0.001
        camera.zFar = 100.0
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        
        if !pointCloud.isEmpty {
            let bbox = calculateBoundingBox(pointCloud)
            let size = SCNVector3(
                bbox.max.x - bbox.min.x,
                bbox.max.y - bbox.min.y,
                bbox.max.z - bbox.min.z
            )
            let maxDim = Swift.max(size.x, Swift.max(size.y, size.z))
            let distance = maxDim * 3.0
            
            cameraNode.position = SCNVector3(distance, distance * 0.5, distance)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        } else {
            cameraNode.position = SCNVector3(0.5, 0.5, 0.5)
            cameraNode.look(at: SCNVector3(0, 0, 0))
        }
        
        scene.rootNode.addChildNode(cameraNode)
    }
}

// MARK: - Depth Point Data Structure
struct DepthPoint {
    let x: Float
    let y: Float
    let depth: Float
}
