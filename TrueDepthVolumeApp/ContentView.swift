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

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var volumeManager = VolumeButtonManager()
    @State private var showOverlayView = false

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
                    
                    // 3D View button (only show if we have a cropped file)
                    if cameraManager.croppedFileToShare != nil {
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
            if let croppedFileURL = cameraManager.croppedFileToShare {
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
        let processedDepthData: AVDepthData
        let isDisparityData: Bool
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            isDisparityData = true
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

        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = cropPath != nil ? "depth_data_cropped_\(timestamp).csv" : "depth_data_\(timestamp).csv"
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            self.presentError("Could not access Documents directory.")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            var csvContent = "x,y,depth_meters,depth_geometry\n"
            
            var minDepth: Float = Float.infinity
            var maxDepth: Float = -Float.infinity
            var validPixelCount = 0
            var croppedPixelCount = 0
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
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
                        var processedDepth = depthValue
                        if isDisparityData && depthValue > 0 {
                            if depthValue < 1.0 {
                                processedDepth = 1.0 / depthValue
                            }
                        }
                        
                        csvContent += "\(x),\(y),\(String(format: "%.6f", depthValue)),\(String(format: "%.6f", processedDepth))\n"
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
                
                print("✅ Depth data saved successfully!")
                print("📍 File location: \(fileURL.path)")
                print("📊 Dimensions: \(width) x \(height)")
                print("📊 Valid pixels: \(validPixelCount)/\(width * height)")
                if cropPath != nil {
                    print("✂️ Cropped pixels: \(croppedPixelCount)/\(width * height)")
                }
                print("📊 Depth range: \(String(format: "%.6f", validMinDepth))m - \(String(format: "%.6f", validMaxDepth))m")
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

// MARK: - 3D Depth Visualization View
import SceneKit

struct DepthVisualization3DView: View {
    let csvFileURL: URL
    let onDismiss: () -> Void
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    
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
                    
                    Text("3D Depth Visualization")
                        .foregroundColor(.white)
                        .font(.headline)
                    
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
                        Text("Loading 3D Model...")
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
        
        // Skip header line
        for line in lines.dropFirst() {
            let components = line.components(separatedBy: ",")
            guard components.count >= 4,
                  let x = Float(components[0]),
                  let y = Float(components[1]),
                  let depth = Float(components[2]) else { continue }
            
            // Skip invalid depth values
            if depth.isNaN || depth.isInfinite || depth <= 0 { continue }
            
            points.append(DepthPoint(x: x, y: y, depth: depth))
        }
        
        return points
    }
    
    private func create3DScene(from points: [DepthPoint]) -> SCNScene {
        let scene = SCNScene()
        
        // Create point cloud geometry
        let geometry = createPointCloudGeometry(from: points)
        let node = SCNNode(geometry: geometry)
        
        // Position the object at the center
        centerObject(node, points: points)
        
        scene.rootNode.addChildNode(node)
        
        // Add lighting
        setupLighting(scene: scene)
        
        // Setup camera
        setupCamera(scene: scene, points: points)
        
        return scene
    }
    
    private func createPointCloudGeometry(from points: [DepthPoint]) -> SCNGeometry {
        // Create custom geometry with vertices
        var vertices: [SCNVector3] = []
        var colors: [SCNVector3] = []
        
        // Find depth range for color mapping
        let minDepth = points.map { $0.depth }.min() ?? 0
        let maxDepth = points.map { $0.depth }.max() ?? 1
        let depthRange = maxDepth - minDepth
        
        for point in points {
            // Convert to 3D coordinates
            // X stays X, Y becomes Z (depth in scene), depth becomes Y (height)
            let vertex = SCNVector3(
                x: point.x / 100.0,  // Scale down for better visualization
                y: -point.depth * 10.0,  // Depth becomes height (negative for proper orientation)
                z: point.y / 100.0   // Y becomes Z
            )
            vertices.append(vertex)
            
            // Color based on depth (closer = red, farther = blue)
            let normalizedDepth = depthRange > 0 ? (point.depth - minDepth) / depthRange : 0
            let color = depthToColor(normalizedDepth)
            colors.append(color)
        }
        
        // Create geometry source for vertices
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
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
        let indices: [UInt32] = Array(0..<UInt32(vertices.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: vertices.count,
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
    
    private func centerObject(_ node: SCNNode, points: [DepthPoint]) {
        guard !points.isEmpty else { return }
        
        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        
        let centerX = (minX + maxX) / 2.0 / 100.0
        let centerZ = (minY + maxY) / 2.0 / 100.0
        
        node.position = SCNVector3(-centerX, 0, -centerZ)
    }
    
    private func setupLighting(scene: SCNScene) {
        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Directional light
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = UIColor.white
        directionalLight.intensity = 500
        let lightNode = SCNNode()
        lightNode.light = directionalLight
        lightNode.position = SCNVector3(0, 10, 10)
        lightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(lightNode)
    }
    
    private func setupCamera(scene: SCNScene, points: [DepthPoint]) {
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        
        // Position camera to get a good view of the object
        let maxDepth = points.map { $0.depth }.max() ?? 1
        let cameraDistance = Double(maxDepth * 15.0) // Adjust multiplier as needed
        cameraNode.position = SCNVector3(0, cameraDistance * 0.3, cameraDistance)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        
        scene.rootNode.addChildNode(cameraNode)
    }
}

// MARK: - Depth Point Data Structure
struct DepthPoint {
    let x: Float
    let y: Float
    let depth: Float
}
