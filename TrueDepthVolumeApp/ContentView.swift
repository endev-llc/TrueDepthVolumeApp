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
                
                // Show buttons when data is captured OR CSV is uploaded and processed
                if cameraManager.capturedDepthImage != nil {
                    VStack(spacing: 15) {
                        HStack(spacing: 15) {
                            Button(action: {
                                showOverlayView = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "wand.and.rays")
                                        .font(.headline)
                                    Text("Smart Crop")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(15)
                            }
                            
                            Button(action: {
                                cameraManager.showShareSheet = true
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.headline)
                                    Text("Export")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(15)
                            }
                            .disabled(cameraManager.fileToShare == nil && cameraManager.croppedFileToShare == nil)
                        }
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
            if let depthImage = cameraManager.capturedDepthImage {
                OverlayView(
                    depthImage: depthImage,
                    photo: cameraManager.capturedPhoto, // This can be nil for uploaded CSV
                    cameraManager: cameraManager,
                    onDismiss: { showOverlayView = false }
                )
            }
        }
        .fullScreenCover(isPresented: $cameraManager.show3DView) {
            // Prioritize cropped file, then fall back to uploaded CSV
            if let croppedFileURL = cameraManager.croppedFileToShare {
                DepthVisualization3DView(
                    csvFileURL: croppedFileURL,
                    onDismiss: { cameraManager.show3DView = false }
                )
            } else if let uploadedCSV = uploadedCSVFile {
                DepthVisualization3DView(
                    csvFileURL: uploadedCSV,
                    onDismiss: { cameraManager.show3DView = false }
                )
            }
        }
        .onReceive(volumeManager.$volumePressed) { pressed in
            if pressed {
                cameraManager.captureDepthAndPhoto()
            }
        }
        .onChange(of: uploadedCSVFile) { _, newFile in
            if let file = newFile {
                cameraManager.processUploadedCSV(file)
            }
        }
    }
}

// MARK: - Enhanced Overlay View with Drawing
struct OverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let onDismiss: () -> Void
    @State private var drawingId = UUID()
    
    @State private var photoOpacity: Double = 0.7
    @State private var showingDepthOnly = false
    @State private var isDrawingMode = false
    @State private var drawnPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var imageFrame: CGRect = .zero
    @State private var isAutoSegmenting = false
    
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
                    
                    if !isDrawingMode && !isAutoSegmenting {
                        HStack(spacing: 10) {
                            if photo != nil {
                                Button(showingDepthOnly ? "Show Both" : "Depth Only") {
                                    showingDepthOnly.toggle()
                                }
                                .foregroundColor(.white)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.3))
                                .cornerRadius(8)
                            }
                            
                            // AUTO-SEGMENT BUTTON
                            Button(action: autoSegmentObject) {
                                HStack(spacing: 4) {
                                    Image(systemName: "wand.and.rays")
                                    Text("Auto")
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(10)
                            
                            // Manual draw button
                            Button("Manual") {
                                isDrawingMode = true
                                drawnPath = []
                            }
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(8)
                        }
                        
                    } else if isDrawingMode {
                        HStack(spacing: 10) {
                            Button("Clear") {
                                drawnPath = []
                                isDrawing = false
                                drawingId = UUID()
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                            
                            Button("Cancel") {
                                isDrawingMode = false
                                drawnPath = []
                            }
                            .foregroundColor(.white)
                            .font(.caption)
                            
                            if drawnPath.count > 10 {
                                Button("Confirm") {
                                    cropCSVWithOutline()
                                    isDrawingMode = false
                                }
                                .foregroundColor(.green)
                                .font(.caption)
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal)
                        
                    } else if isAutoSegmenting {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("Detecting...")
                                .foregroundColor(.white)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.3))
                        .cornerRadius(10)
                    }
                }
                
                // Opacity slider
                if !showingDepthOnly && photo != nil && !isAutoSegmenting {
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
                
                // Image with overlay
                GeometryReader { geometry in
                    ZStack {
                        // Depth image
                        Image(uiImage: depthImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onAppear {
                                calculateImageFrame(containerSize: geometry.size)
                            }
                            .onChange(of: geometry.size) { _, newSize in
                                calculateImageFrame(containerSize: newSize)
                            }
                        
                        // Photo overlay
                        if !showingDepthOnly, let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // Drawing overlay
                        DrawingOverlay(
                            path: $drawnPath,
                            isDrawing: $isDrawing,
                            frameSize: geometry.size,
                            imageFrame: imageFrame
                        )
                        .id(drawingId)
                        .allowsHitTesting(isDrawingMode)
                        .opacity(isDrawingMode ? 1.0 : 0.0)
                        
                        // Show completed outline
                        if !isDrawingMode && !drawnPath.isEmpty && !isAutoSegmenting {
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
                
                // Instruction text
                Text(getInstructionText())
                    .foregroundColor(getInstructionColor())
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
    
    private func calculateImageFrame(containerSize: CGSize) {
        let imageAspectRatio = depthImage.size.width / depthImage.size.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        if imageAspectRatio > containerAspectRatio {
            let imageHeight = containerSize.width / imageAspectRatio
            let yOffset = (containerSize.height - imageHeight) / 2
            imageFrame = CGRect(x: 0, y: yOffset, width: containerSize.width, height: imageHeight)
        } else {
            let imageWidth = containerSize.height * imageAspectRatio
            let xOffset = (containerSize.width - imageWidth) / 2
            imageFrame = CGRect(x: xOffset, y: 0, width: imageWidth, height: containerSize.height)
        }
    }
    
    private func getInstructionText() -> String {
        if isAutoSegmenting {
            return "AI is analyzing depth patterns..."
        } else if isDrawingMode {
            return "Draw around the object. Tap 'Confirm' when done."
        } else if !drawnPath.isEmpty {
            return "Object detected! Tap 'Done' to proceed."
        } else {
            return "Tap 'Auto' for AI detection or 'Manual' to draw"
        }
    }
    
    private func getInstructionColor() -> Color {
        if isAutoSegmenting {
            return .cyan
        } else if !drawnPath.isEmpty {
            return .green
        } else {
            return .white
        }
    }
    
    private func autoSegmentObject() {
        isAutoSegmenting = true
        drawnPath = []
        
        cameraManager.autoSegmentPrimaryObject { autoPath in
            DispatchQueue.main.async {
                self.isAutoSegmenting = false
                
                if let path = autoPath {
                    self.drawnPath = path
                    self.drawingId = UUID()
                    
                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                } else {
                    // Fall back to manual mode if auto fails
                    self.isDrawingMode = true
                }
            }
        }
    }
    
    private func cropCSVWithOutline() {
        let imageSize = depthImage.size
        let scaledPath = drawnPath.map { point in
            let relativeX = (point.x - imageFrame.minX) / imageFrame.width
            let relativeY = (point.y - imageFrame.minY) / imageFrame.height
            
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
    private var uploadedCSVData: [DepthPoint] = [] // Store uploaded CSV data for cropping

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

    // MARK: - Process Uploaded CSV
    func processUploadedCSV(_ fileURL: URL) {
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let csvContent = try String(contentsOf: fileURL)
                let depthPoints = self.parseCSVContent(csvContent)
                
                // Store the depth points for cropping
                self.uploadedCSVData = depthPoints
                
                // Create depth visualization in portrait orientation
                let depthImage = self.createDepthVisualizationFromCSV(depthPoints)
                
                DispatchQueue.main.async {
                    self.capturedDepthImage = depthImage
                    self.capturedPhoto = nil // No photo for uploaded CSV
                    self.fileToShare = fileURL
                    self.isProcessing = false
                    
                    // Set a filename for display
                    self.lastSavedFileName = fileURL.lastPathComponent
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to process CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func parseCSVContent(_ content: String) -> [DepthPoint] {
        var points: [DepthPoint] = []
        let lines = content.components(separatedBy: .newlines)
        
        // Parse camera intrinsics from comments if available
        for line in lines {
            if line.hasPrefix("# Camera Intrinsics:") {
                // Parse camera intrinsics and store them
                // This is simplified - you might want to add full parsing
                break
            }
        }
        
        for line in lines {
            if line.hasPrefix("#") || line.contains("x,y,depth") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            let components = line.components(separatedBy: ",")
            if components.count >= 3 {
                guard let x = Float(components[0]),
                      let y = Float(components[1]),
                      let depth = Float(components[2]) else { continue }
                
                if depth.isNaN || depth.isInfinite || depth <= 0 { continue }
                
                points.append(DepthPoint(x: x, y: y, depth: depth))
            }
        }
        
        return points
    }
    
    private func createDepthVisualizationFromCSV(_ points: [DepthPoint]) -> UIImage? {
        guard !points.isEmpty else { return nil }
        
        // Determine original image dimensions based on data
        let maxX = Int(ceil(points.map { $0.x }.max() ?? 0))
        let maxY = Int(ceil(points.map { $0.y }.max() ?? 0))
        
        let originalWidth = maxX + 1
        let originalHeight = maxY + 1
        
        // Create rotated dimensions to match camera capture orientation (90° rotation)
        let rotatedWidth = originalHeight  // Swap width and height like camera capture
        let rotatedHeight = originalWidth
        
        // Find min/max depth for normalization
        let depthValues = points.map { $0.depth }.filter { !$0.isNaN && !$0.isInfinite && $0 > 0 }
        guard !depthValues.isEmpty else { return nil }
        
        let minDepth = depthValues.min()!
        let maxDepth = depthValues.max()!
        
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
        
        // Initialize with black background
        for i in 0..<(rotatedWidth * rotatedHeight * 4) {
            data[i] = 0
        }
        
        // Apply jet colormap
        let jetColormap: [[Float]] = [
            [0, 0, 128], [0, 0, 255], [0, 128, 255], [0, 255, 255],
            [128, 255, 128], [255, 255, 0], [255, 128, 0], [255, 0, 0], [128, 0, 0]
        ]
        
        for point in points {
            let x = Int(point.x)
            let y = Int(point.y)
            
            guard x >= 0 && x < originalWidth && y >= 0 && y < originalHeight else { continue }
            
            let normalizedDepth = (point.depth - minDepth) / (maxDepth - minDepth)
            let invertedDepth = 1.0 - normalizedDepth
            let color = interpolateColor(colormap: jetColormap, t: invertedDepth)
            
            // Apply same rotation as camera capture: (x,y) -> (originalHeight-1-y, x)
            let rotatedX = originalHeight - 1 - y
            let rotatedY = x
            let dataIndex = (rotatedY * rotatedWidth + rotatedX) * 4
            
            data[dataIndex] = UInt8(color[0])     // R
            data[dataIndex + 1] = UInt8(color[1]) // G
            data[dataIndex + 2] = UInt8(color[2]) // B
            data[dataIndex + 3] = 255             // A
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Depth Data Delegate
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        self.latestDepthData = depthData
        
        // Capture camera calibration data for accurate coordinate conversion
        if let calibrationData = depthData.cameraCalibrationData {
            self.cameraCalibrationData = calibrationData
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

    // MARK: - CSV Cropping Function (Updated to handle uploaded CSV)
    func cropDepthDataWithPath(_ path: [CGPoint]) {
        if !uploadedCSVData.isEmpty {
            // Handle uploaded CSV cropping
            cropUploadedCSVWithPath(path)
        } else if let depthData = rawDepthData {
            // Handle camera-captured depth data cropping
            saveDepthDataToFile(depthData: depthData, cropPath: path)
        } else {
            presentError("No depth data available for cropping.")
            return
        }
        
        DispatchQueue.main.async {
            self.hasOutline = true
        }
    }
    
    private func cropUploadedCSVWithPath(_ path: [CGPoint]) {
        guard !uploadedCSVData.isEmpty else { return }
        
        // Show processing indicator
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "depth_data_cropped_\(timestamp).csv"
            
            guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async {
                    self.presentError("Could not access Documents directory.")
                    self.isProcessing = false
                }
                return
            }
            
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            do {
                var csvLines: [String] = []
                csvLines.append("x,y,depth_meters")
                
                // READ AND PRESERVE CAMERA INTRINSICS FROM ORIGINAL FILE (same as camera capture)
                if let originalFileURL = self.fileToShare {
                    let originalContent = try String(contentsOf: originalFileURL)
                    let originalLines = originalContent.components(separatedBy: .newlines)
                    
                    // Copy all comment lines from original file (preserves intrinsics)
                    for line in originalLines {
                        if line.hasPrefix("#") {
                            csvLines.append(line)
                        }
                    }
                }
                
                // Add cropping metadata (same as camera capture)
                csvLines.append("# Cropped from uploaded CSV file")
                
                var croppedPixelCount = 0
                
                // Get original data dimensions (same as camera capture logic)
                let originalMaxX = Int(ceil(self.uploadedCSVData.map { $0.x }.max() ?? 0))
                let originalMaxY = Int(ceil(self.uploadedCSVData.map { $0.y }.max() ?? 0))
                let originalWidth = originalMaxX + 1
                let originalHeight = originalMaxY + 1
                
                // Simplify path for faster processing (same as camera capture)
                let simplifiedPath = self.douglasPeuckerSimplify(path, epsilon: 1.0)
                
                var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
                if !simplifiedPath.isEmpty {
                    let minX = Int(floor(simplifiedPath.map { $0.x }.min()!))
                    let maxX = Int(ceil(simplifiedPath.map { $0.x }.max()!))
                    let minY = Int(floor(simplifiedPath.map { $0.y }.min()!))
                    let maxY = Int(ceil(simplifiedPath.map { $0.y }.max()!))
                    
                    boundingBox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
                }
                
                print("Cropping \(self.uploadedCSVData.count) points...")
                
                // Track depth statistics (same as camera capture)
                var minDepth: Float = Float.infinity
                var maxDepth: Float = -Float.infinity
                var validPixelCount = 0
                
                // Process each point using EXACTLY the same logic as camera capture
                for point in self.uploadedCSVData {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    
                    var shouldInclude = true
                    
                    if let bbox = boundingBox {
                        // Transform to display coordinates using SAME rotation as camera capture
                        let displayX = originalHeight - 1 - y  // Same as camera: height - 1 - y
                        let displayY = x                       // Same as camera: x
                        
                        if displayX < bbox.minX || displayX > bbox.maxX ||
                           displayY < bbox.minY || displayY > bbox.maxY {
                            shouldInclude = false
                        } else {
                            let displayPoint = CGPoint(x: CGFloat(displayX), y: CGFloat(displayY))
                            shouldInclude = self.fastPointInPolygon(point: displayPoint, polygon: simplifiedPath)
                        }
                    }
                    
                    if shouldInclude {
                        csvLines.append("\(point.x),\(point.y),\(String(format: "%.6f", point.depth))")
                        croppedPixelCount += 1
                        
                        // Track depth stats (same as camera capture)
                        if !point.depth.isNaN && !point.depth.isInfinite && point.depth > 0 {
                            minDepth = min(minDepth, point.depth)
                            maxDepth = max(maxDepth, point.depth)
                            validPixelCount += 1
                        }
                    }
                }
                
                let csvContent = csvLines.joined(separator: "\n")
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                print("Successfully cropped \(croppedPixelCount) points from \(self.uploadedCSVData.count) total points")
                print("Depth range: \(minDepth) to \(maxDepth) meters, \(validPixelCount) valid depth values")
                
                DispatchQueue.main.async {
                    self.lastSavedFileName = fileName
                    self.croppedFileToShare = fileURL
                    self.isProcessing = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to save cropped CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
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
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                self.presentError("Failed to convert disparity to depth: \(error.localizedDescription)")
                return
            }
        } else {
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
            var csvLines: [String] = []
            csvLines.append("x,y,depth_meters")
            
            if let calibrationData = self.cameraCalibrationData {
                let intrinsics = calibrationData.intrinsicMatrix
                csvLines.append("# Camera Intrinsics: fx=\(intrinsics.columns.0.x), fy=\(intrinsics.columns.1.y), cx=\(intrinsics.columns.2.x), cy=\(intrinsics.columns.2.y)")
                let dimensions = calibrationData.intrinsicMatrixReferenceDimensions
                csvLines.append("# Reference Dimensions: width=\(dimensions.width), height=\(dimensions.height)")
            }
            
            let originalDataType = depthData.depthDataType
            if originalDataType == kCVPixelFormatType_DisparityFloat16 || originalDataType == kCVPixelFormatType_DisparityFloat32 {
                csvLines.append("# Original Data: Disparity (converted to depth using Apple's calibrated conversion)")
            } else {
                csvLines.append("# Original Data: Depth")
            }
            
            var minDepth: Float = Float.infinity
            var maxDepth: Float = -Float.infinity
            var validPixelCount = 0
            var croppedPixelCount = 0
            
            var boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
            var simplifiedPath: [CGPoint] = []
            
            if let cropPath = cropPath {
                simplifiedPath = douglasPeuckerSimplify(cropPath, epsilon: 1.0)
                
                let minX = Int(floor(simplifiedPath.map { $0.x }.min()!))
                let maxX = Int(ceil(simplifiedPath.map { $0.x }.max()!))
                let minY = Int(floor(simplifiedPath.map { $0.y }.min()!))
                let maxY = Int(ceil(simplifiedPath.map { $0.y }.max()!))
                
                boundingBox = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            }
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
                    var shouldInclude = true
                    
                    if let bbox = boundingBox {
                        let displayX = height - 1 - y
                        let displayY = x
                        
                        if displayX < bbox.minX || displayX > bbox.maxX ||
                           displayY < bbox.minY || displayY > bbox.maxY {
                            shouldInclude = false
                        } else {
                            let point = CGPoint(x: CGFloat(displayX), y: CGFloat(displayY))
                            shouldInclude = fastPointInPolygon(point: point, polygon: simplifiedPath)
                        }
                    }
                    
                    if shouldInclude {
                        csvLines.append("\(x),\(y),\(String(format: "%.6f", depthValue))")
                        croppedPixelCount += 1
                        
                        if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                            minDepth = min(minDepth, depthValue)
                            maxDepth = max(maxDepth, depthValue)
                            validPixelCount += 1
                        }
                    }
                }
            }
            
            let csvContent = csvLines.joined(separator: "\n")
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            DispatchQueue.main.async {
                self.lastSavedFileName = fileName
                if cropPath != nil {
                    self.croppedFileToShare = fileURL
                } else {
                    self.fileToShare = fileURL
                }
            }
            
        } catch {
            self.presentError("Failed to save depth data: \(error.localizedDescription)")
        }
    }

    // Optimized point-in-polygon using winding number algorithm
    private func fastPointInPolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        
        let x = point.x
        let y = point.y
        var windingNumber = 0
        
        for i in 0..<polygon.count {
            let j = (i + 1) % polygon.count
            
            let xi = polygon[i].x
            let yi = polygon[i].y
            let xj = polygon[j].x
            let yj = polygon[j].y
            
            if yi <= y {
                if yj > y {  // upward crossing
                    let cross = (xj - xi) * (y - yi) - (x - xi) * (yj - yi)
                    if cross > 0 {
                        windingNumber += 1
                    }
                }
            } else {
                if yj <= y { // downward crossing
                    let cross = (xj - xi) * (y - yi) - (x - xi) * (yj - yi)
                    if cross < 0 {
                        windingNumber -= 1
                    }
                }
            }
        }
        
        return windingNumber != 0
    }

    // Douglas-Peucker algorithm for polygon simplification
    private func douglasPeuckerSimplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        
        // Find the point with maximum distance from line between first and last points
        var maxDistance: CGFloat = 0
        var maxIndex = 0
        
        let firstPoint = points.first!
        let lastPoint = points.last!
        
        for i in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[i], lineStart: firstPoint, lineEnd: lastPoint)
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }
        
        // If max distance is greater than epsilon, recursively simplify
        if maxDistance > epsilon {
            let leftSegment = douglasPeuckerSimplify(Array(points[0...maxIndex]), epsilon: epsilon)
            let rightSegment = douglasPeuckerSimplify(Array(points[maxIndex..<points.count]), epsilon: epsilon)
            
            // Combine results (remove duplicate middle point)
            return leftSegment + Array(rightSegment.dropFirst())
        } else {
            // Return just the endpoints
            return [firstPoint, lastPoint]
        }
    }

    private func perpendicularDistance(_ point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        
        if dx == 0 && dy == 0 {
            // Line segment is a point
            let px = point.x - lineStart.x
            let py = point.y - lineStart.y
            return sqrt(px * px + py * py)
        }
        
        let numerator = abs(dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x)
        let denominator = sqrt(dx * dx + dy * dy)
        
        return numerator / denominator
    }
}

extension CameraManager {
    
    // MARK: - Main Auto-Segmentation Function (Keep this unchanged)
    func autoSegmentPrimaryObject(completion: @escaping ([CGPoint]?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var segmentationPath: [CGPoint]?
            
            if !self.uploadedCSVData.isEmpty {
                // Process uploaded CSV data
                segmentationPath = self.autoSegmentFromCSVData(self.uploadedCSVData)
            } else if let depthData = self.rawDepthData {
                // Process camera-captured depth data
                segmentationPath = self.autoSegmentFromDepthData(depthData)
            }
            
            DispatchQueue.main.async {
                completion(segmentationPath)
            }
        }
    }
    
    // MARK: - CSV and Camera Processing (Keep these unchanged)
    private func autoSegmentFromCSVData(_ points: [DepthPoint]) -> [CGPoint]? {
        guard !points.isEmpty else { return nil }
        
        let maxX = Int(ceil(points.map { $0.x }.max() ?? 0))
        let maxY = Int(ceil(points.map { $0.y }.max() ?? 0))
        let width = maxX + 1
        let height = maxY + 1
        
        var depthMap = Array(repeating: Array(repeating: Float.infinity, count: width), count: height)
        
        for point in points {
            let x = Int(point.x)
            let y = Int(point.y)
            if x >= 0 && x < width && y >= 0 && y < height && point.depth > 0 && !point.depth.isNaN {
                depthMap[y][x] = point.depth
            }
        }
        
        return performDepthBasedSegmentation(depthMap: depthMap, originalWidth: width, originalHeight: height)
    }
    
    private func autoSegmentFromDepthData(_ depthData: AVDepthData) -> [CGPoint]? {
        let processedDepthData: AVDepthData
        
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                print("Failed to convert depth data: \(error)")
                return nil
            }
        } else {
            processedDepthData = depthData
        }
        
        let depthMap = processedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var depthArray = Array(repeating: Array(repeating: Float.infinity, count: width), count: height)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    depthArray[y][x] = depthValue
                }
            }
        }
        
        return performDepthBasedSegmentation(depthMap: depthArray, originalWidth: width, originalHeight: height)
    }
    
    // MARK: - Advanced Preprocessing Functions
    private func advancedPreprocessing(_ depthMap: [[Float]]) -> [[Float]] {
        let height = depthMap.count
        let width = depthMap[0].count
        var processed = depthMap
        
        // Intelligent hole filling with weighted neighbors
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                if processed[y][x].isInfinite {
                    var weightedSum: Float = 0
                    var totalWeight: Float = 0
                    
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let neighborDepth = processed[y+dy][x+dx]
                            if !neighborDepth.isInfinite && neighborDepth > 0 {
                                let distance = sqrt(Float(dx*dx + dy*dy))
                                let weight = 1.0 / (1.0 + distance)
                                weightedSum += neighborDepth * weight
                                totalWeight += weight
                            }
                        }
                    }
                    
                    if totalWeight > 0 {
                        processed[y][x] = weightedSum / totalWeight
                    }
                }
            }
        }
        
        return processed
    }
    
    private func calculateDetailedDepthStatistics(_ depthMap: [[Float]]) -> (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)? {
        var validDepths: [Float] = []
        
        for row in depthMap {
            for depth in row {
                if !depth.isInfinite && depth > 0 && !depth.isNaN {
                    validDepths.append(depth)
                }
            }
        }
        
        guard !validDepths.isEmpty else { return nil }
        
        validDepths.sort()
        let minDepth = validDepths.first!
        let maxDepth = validDepths.last!
        let medianDepth = validDepths[validDepths.count / 2]
        let meanDepth = validDepths.reduce(0, +) / Float(validDepths.count)
        
        // Calculate standard deviation
        let variance = validDepths.map { pow($0 - meanDepth, 2) }.reduce(0, +) / Float(validDepths.count)
        let stdDev = sqrt(variance)
        
        return (minDepth, maxDepth, meanDepth, medianDepth, stdDev)
    }
    
    private func detectBackgroundWithConfidence(_ depthMap: [[Float]], stats: (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)) -> (depth: Float, confidence: Float) {
        
        let numBins = 100
        let binSize = (stats.maxDepth - stats.minDepth) / Float(numBins)
        var histogram = Array(repeating: 0, count: numBins)
        
        for row in depthMap {
            for depth in row {
                if !depth.isInfinite && depth > 0 {
                    let binIndex = min(numBins - 1, max(0, Int((depth - stats.minDepth) / binSize)))
                    histogram[binIndex] += 1
                }
            }
        }
        
        let maxCount = histogram.max() ?? 0
        let maxBinIndex = histogram.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let backgroundDepth = stats.minDepth + Float(maxBinIndex) * binSize + binSize / 2
        
        let totalPixels = depthMap.flatMap { $0 }.filter { !$0.isInfinite && $0 > 0 }.count
        let confidence = Float(maxCount) / Float(totalPixels)
        
        return (backgroundDepth, confidence)
    }
    
    private func createAdaptiveObjectMask(_ depthMap: [[Float]], backgroundInfo: (depth: Float, confidence: Float), stats: (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)) -> [[Bool]] {
        
        let height = depthMap.count
        let width = depthMap[0].count
        var mask = Array(repeating: Array(repeating: false, count: width), count: height)
        
        let baseThreshold: Float = backgroundInfo.confidence > 0.3 ? 0.05 : 0.08
        let depthRange = stats.maxDepth - stats.minDepth
        let globalThreshold = backgroundInfo.depth - depthRange * baseThreshold
        
        print("🎯 Using adaptive threshold: \(globalThreshold) (base: \(baseThreshold))")
        
        for y in 0..<height {
            for x in 0..<width {
                let depth = depthMap[y][x]
                if depth.isInfinite || depth <= 0 { continue }
                
                mask[y][x] = depth < globalThreshold
            }
        }
        
        return mask
    }
    
    private func combineDepthAndEdgeDetection(_ depthMap: [[Float]], objectMask: [[Bool]], stats: (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)) -> [[Bool]] {
        
        let height = depthMap.count
        let width = depthMap[0].count
        var combinedMask = objectMask
        
        // Sobel edge detection
        let sobelX: [[Float]] = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
        let sobelY: [[Float]] = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]
        
        var edgeMagnitude = Array(repeating: Array(repeating: Float(0), count: width), count: height)
        
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                var gx: Float = 0
                var gy: Float = 0
                
                for ky in 0..<3 {
                    for kx in 0..<3 {
                        let depth = depthMap[y+ky-1][x+kx-1]
                        let depthValue = depth.isInfinite ? stats.meanDepth : depth
                        gx += sobelX[ky][kx] * depthValue
                        gy += sobelY[ky][kx] * depthValue
                    }
                }
                
                edgeMagnitude[y][x] = sqrt(gx * gx + gy * gy)
            }
        }
        
        let sortedEdges = edgeMagnitude.flatMap { $0 }.sorted()
        let edgeThreshold = sortedEdges[Int(Float(sortedEdges.count) * 0.85)]
        
        print("🔧 Edge threshold: \(edgeThreshold)")
        
        // Enhance object mask with strong edges
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                if edgeMagnitude[y][x] > edgeThreshold {
                    var nearObject = false
                    for dy in -2...2 {
                        for dx in -2...2 {
                            let ny = y + dy
                            let nx = x + dx
                            if ny >= 0 && ny < height && nx >= 0 && nx < width && objectMask[ny][nx] {
                                nearObject = true
                                break
                            }
                        }
                        if nearObject { break }
                    }
                    
                    if nearObject {
                        combinedMask[y][x] = true
                    }
                }
            }
        }
        
        return combinedMask
    }
    
    // MARK: - Morphological Operations (THESE WERE MISSING)
    private func morphologicalErosion(_ mask: [[Bool]], kernelSize: Int) -> [[Bool]] {
        let height = mask.count
        let width = mask[0].count
        var result = Array(repeating: Array(repeating: false, count: width), count: height)
        let half = kernelSize / 2
        
        for y in half..<(height-half) {
            for x in half..<(width-half) {
                var allTrue = true
                for ky in -half...half {
                    for kx in -half...half {
                        if !mask[y+ky][x+kx] {
                            allTrue = false
                            break
                        }
                    }
                    if !allTrue { break }
                }
                result[y][x] = allTrue
            }
        }
        
        return result
    }
    
    private func morphologicalDilation(_ mask: [[Bool]], kernelSize: Int) -> [[Bool]] {
        let height = mask.count
        let width = mask[0].count
        var result = Array(repeating: Array(repeating: false, count: width), count: height)
        let half = kernelSize / 2
        
        for y in half..<(height-half) {
            for x in half..<(width-half) {
                var anyTrue = false
                for ky in -half...half {
                    for kx in -half...half {
                        if mask[y+ky][x+kx] {
                            anyTrue = true
                            break
                        }
                    }
                    if anyTrue { break }
                }
                result[y][x] = anyTrue
            }
        }
        
        return result
    }
    
    private func intelligentMorphologicalCleaning(_ mask: [[Bool]]) -> [[Bool]] {
        // Remove small noise
        var cleaned = morphologicalErosion(mask, kernelSize: 2)
        // Fill small gaps
        cleaned = morphologicalDilation(cleaned, kernelSize: 4)
        // Smooth boundaries
        cleaned = morphologicalDilation(cleaned, kernelSize: 3)
        cleaned = morphologicalErosion(cleaned, kernelSize: 3)
        
        return cleaned
    }
    
    // MARK: - Connected Component Analysis
    private func findBestConnectedComponent(_ mask: [[Bool]], originalMask: [[Bool]]) -> [[Bool]] {
        let height = mask.count
        let width = mask[0].count
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        var bestComponent = Array(repeating: Array(repeating: false, count: width), count: height)
        var bestScore = 0.0
        
        func floodFill(_ startX: Int, _ startY: Int) -> (component: [(Int, Int)], score: Double) {
            var component: [(Int, Int)] = []
            var stack: [(Int, Int)] = [(startX, startY)]
            var originalPixels = 0
            
            while !stack.isEmpty {
                let (x, y) = stack.removeLast()
                
                if x < 0 || x >= width || y < 0 || y >= height || visited[y][x] || !mask[y][x] {
                    continue
                }
                
                visited[y][x] = true
                component.append((x, y))
                
                if originalMask[y][x] {
                    originalPixels += 1
                }
                
                stack.append(contentsOf: [(x+1, y), (x-1, y), (x, y+1), (x, y-1)])
            }
            
            let consistencyScore = component.isEmpty ? 0.0 : Double(originalPixels) / Double(component.count)
            let sizeScore = Double(component.count)
            let combinedScore = sizeScore * (0.3 + 0.7 * consistencyScore)
            
            return (component, combinedScore)
        }
        
        for y in 0..<height {
            for x in 0..<width {
                if mask[y][x] && !visited[y][x] {
                    let result = floodFill(x, y)
                    if result.score > bestScore {
                        bestScore = result.score
                        bestComponent = Array(repeating: Array(repeating: false, count: width), count: height)
                        for (cx, cy) in result.component {
                            bestComponent[cy][cx] = true
                        }
                    }
                }
            }
        }
        
        print("🎯 Best component score: \(bestScore)")
        return bestComponent
    }
    
    // MARK: - Contour Extraction
    private func extractDetailedContour(_ mask: [[Bool]]) -> [CGPoint] {
        let height = mask.count
        let width = mask[0].count
        
        var boundaryPixels: [CGPoint] = []
        
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                if mask[y][x] {
                    var isBoundary = false
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let nx = x + dx
                            let ny = y + dy
                            if nx >= 0 && nx < width && ny >= 0 && ny < height && !mask[ny][nx] {
                                isBoundary = true
                                break
                            }
                        }
                        if isBoundary { break }
                    }
                    
                    if isBoundary {
                        boundaryPixels.append(CGPoint(x: x, y: y))
                    }
                }
            }
        }
        
        guard !boundaryPixels.isEmpty else { return [] }
        
        print("🔧 Found \(boundaryPixels.count) boundary pixels")
        
        // Create ordered contour
        var orderedContour: [CGPoint] = []
        var remaining = Set(boundaryPixels.map { "\(Int($0.x)),\(Int($0.y))" })
        
        var current = boundaryPixels.min { $0.x < $1.x } ?? boundaryPixels[0]
        
        while !remaining.isEmpty {
            let currentKey = "\(Int(current.x)),\(Int(current.y))"
            if remaining.contains(currentKey) {
                orderedContour.append(current)
                remaining.remove(currentKey)
            }
            
            var nearestDistance: CGFloat = CGFloat.infinity
            var nearestPixel = current
            
            for pixel in boundaryPixels {
                let pixelKey = "\(Int(pixel.x)),\(Int(pixel.y))"
                if remaining.contains(pixelKey) {
                    let distance = sqrt(pow(pixel.x - current.x, 2) + pow(pixel.y - current.y, 2))
                    if distance < nearestDistance && distance < 3.0 {
                        nearestDistance = distance
                        nearestPixel = pixel
                    }
                }
            }
            
            if nearestDistance == CGFloat.infinity {
                for pixel in boundaryPixels {
                    let pixelKey = "\(Int(pixel.x)),\(Int(pixel.y))"
                    if remaining.contains(pixelKey) {
                        let distance = sqrt(pow(pixel.x - current.x, 2) + pow(pixel.y - current.y, 2))
                        if distance < nearestDistance {
                            nearestDistance = distance
                            nearestPixel = pixel
                        }
                    }
                }
            }
            
            current = nearestPixel
            
            if orderedContour.count > boundaryPixels.count * 2 {
                break
            }
        }
        
        return orderedContour
    }
    
    private func intelligentContourRefinement(_ contour: [CGPoint]) -> [CGPoint] {
        guard contour.count > 10 else { return contour }
        
        var smoothed = contour
        if contour.count > 20 {
            smoothed = []
            let windowSize = 3
            
            for i in 0..<contour.count {
                var avgX: CGFloat = 0
                var avgY: CGFloat = 0
                
                for j in 0..<windowSize {
                    let index = (i + j - windowSize/2 + contour.count) % contour.count
                    avgX += contour[index].x
                    avgY += contour[index].y
                }
                
                avgX /= CGFloat(windowSize)
                avgY /= CGFloat(windowSize)
                smoothed.append(CGPoint(x: avgX, y: avgY))
            }
        }
        
        let simplified = douglasPeuckerSimplify(smoothed, epsilon: 0.8)
        
        print("🔧 Contour refinement: \(contour.count) → \(smoothed.count) → \(simplified.count)")
        
        return simplified
    }
    
    // MARK: - Coordinate Conversion (THIS WAS MISSING)
    private func convertToDisplayCoordinates(_ contour: [CGPoint], originalWidth: Int, originalHeight: Int) -> [CGPoint] {
        // Apply same rotation as your existing overlay: (x,y) -> (originalHeight-1-y, x)
        return contour.map { point in
            let displayX = CGFloat(originalHeight - 1) - point.y
            let displayY = point.x
            return CGPoint(x: displayX, y: displayY)
        }
    }
    
    private func performDepthBasedSegmentation(depthMap: [[Float]], originalWidth: Int, originalHeight: Int) -> [CGPoint]? {
            
            print("🔍 Starting FIXED auto-segmentation on \(originalWidth)x\(originalHeight) depth map")
            
            // Step 1: Better preprocessing
            let processedDepth = improvedPreprocessing(depthMap)
            
            // Step 2: Enhanced statistics
            guard let stats = calculateDetailedDepthStatistics(processedDepth) else {
                print("❌ No valid depth data found")
                return nil
            }
            
            print("📊 Depth analysis:")
            print("   Range: \(stats.minDepth) to \(stats.maxDepth) (\((stats.maxDepth-stats.minDepth)*100)cm)")
            print("   Mean: \(stats.meanDepth), Median: \(stats.medianDepth)")
            print("   StdDev: \(stats.stdDev)")
            
            // Step 3: Multi-threshold approach
            let backgroundInfo = detectBackgroundWithConfidence(processedDepth, stats: stats)
            print("🎯 Background: \(backgroundInfo.depth)m (conf: \(backgroundInfo.confidence))")
            
            // Step 4: Try multiple threshold strategies
            let bestMask = findBestObjectMask(processedDepth, backgroundInfo: backgroundInfo, stats: stats)
            
            // Step 5: Clean up mask
            let cleanedMask = improvedMorphologicalCleaning(bestMask, stats: stats)
            
            // Step 6: Get best component
            let primaryObjectMask = findBestConnectedComponent(cleanedMask, originalMask: bestMask)
            
            // Step 7: PROPER contour tracing using Moore neighborhood algorithm
            let rawContour = mooreNeighborhoodContourTracing(primaryObjectMask)
            guard !rawContour.isEmpty else {
                print("❌ Moore tracing failed, trying backup method")
                return fallbackContourExtraction(primaryObjectMask, originalWidth: originalWidth, originalHeight: originalHeight)
            }
            
            print("🔧 Moore tracing found: \(rawContour.count) contour points")
            
            // Step 8: Conservative refinement (preserve much more detail)
            let refinedContour = conservativeContourRefinement(rawContour, targetPoints: 200)
            
            print("🔧 After refinement: \(refinedContour.count) points")
            
            // Step 9: Convert coordinates
            let displayContour = convertToDisplayCoordinates(
                refinedContour,
                originalWidth: originalWidth,
                originalHeight: originalHeight
            )
            
            print("✅ FIXED segmentation complete: \(displayContour.count) final contour points")
            return displayContour.isEmpty ? nil : displayContour
        }
        
        // MARK: - Improved Preprocessing
        private func improvedPreprocessing(_ depthMap: [[Float]]) -> [[Float]] {
            let height = depthMap.count
            let width = depthMap[0].count
            var processed = depthMap
            
            // Step 1: More intelligent hole filling
            for iteration in 0..<2 { // Multiple passes
                var newProcessed = processed
                
                for y in 1..<(height-1) {
                    for x in 1..<(width-1) {
                        if processed[y][x].isInfinite {
                            var validNeighbors: [(depth: Float, weight: Float)] = []
                            
                            // Check 8-connected neighbors with distance weighting
                            for dy in -1...1 {
                                for dx in -1...1 {
                                    if dy == 0 && dx == 0 { continue }
                                    let neighborDepth = processed[y+dy][x+dx]
                                    if !neighborDepth.isInfinite && neighborDepth > 0 {
                                        let distance = sqrt(Float(dx*dx + dy*dy))
                                        let weight = 1.0 / (1.0 + distance * distance)
                                        validNeighbors.append((neighborDepth, weight))
                                    }
                                }
                            }
                            
                            if validNeighbors.count >= 3 { // Need at least 3 valid neighbors
                                let weightedSum = validNeighbors.reduce(0) { $0 + $1.depth * $1.weight }
                                let totalWeight = validNeighbors.reduce(0) { $0 + $1.weight }
                                newProcessed[y][x] = weightedSum / totalWeight
                            }
                        }
                    }
                }
                processed = newProcessed
            }
            
            // Step 2: Light median filtering to reduce noise
            processed = medianFilter(processed, kernelSize: 3)
            
            return processed
        }
        
        // MARK: - Median Filter
        private func medianFilter(_ depthMap: [[Float]], kernelSize: Int) -> [[Float]] {
            let height = depthMap.count
            let width = depthMap[0].count
            var filtered = depthMap
            let half = kernelSize / 2
            
            for y in half..<(height-half) {
                for x in half..<(width-half) {
                    var neighborhood: [Float] = []
                    
                    for ky in -half...half {
                        for kx in -half...half {
                            let depth = depthMap[y+ky][x+kx]
                            if !depth.isInfinite && depth > 0 {
                                neighborhood.append(depth)
                            }
                        }
                    }
                    
                    if neighborhood.count >= 5 { // Need sufficient valid pixels
                        neighborhood.sort()
                        filtered[y][x] = neighborhood[neighborhood.count / 2]
                    }
                }
            }
            
            return filtered
        }
        
        // MARK: - Multi-threshold Object Detection
        private func findBestObjectMask(_ depthMap: [[Float]], backgroundInfo: (depth: Float, confidence: Float), stats: (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)) -> [[Bool]] {
            
            let height = depthMap.count
            let width = depthMap[0].count
            
            // Try multiple threshold strategies
            let depthRange = stats.maxDepth - stats.minDepth
            
            var thresholds: [Float] = []
            
            if backgroundInfo.confidence > 0.2 {
                // High confidence - use background-based thresholds
                thresholds = [
                    backgroundInfo.depth - depthRange * 0.03, // Very conservative
                    backgroundInfo.depth - depthRange * 0.05, // Conservative
                    backgroundInfo.depth - depthRange * 0.08  // Aggressive
                ]
            } else {
                // Low confidence - use statistical thresholds
                thresholds = [
                    stats.medianDepth - stats.stdDev * 0.5,
                    stats.medianDepth - stats.stdDev * 1.0,
                    stats.medianDepth - stats.stdDev * 1.5
                ]
            }
            
            print("🎯 Trying thresholds: \(thresholds.map { String(format: "%.3f", $0) }.joined(separator: ", "))")
            
            var bestMask: [[Bool]]?
            var bestScore = 0.0
            
            for threshold in thresholds {
                var mask = Array(repeating: Array(repeating: false, count: width), count: height)
                var objectPixels = 0
                
                // Create mask
                for y in 0..<height {
                    for x in 0..<width {
                        let depth = depthMap[y][x]
                        if !depth.isInfinite && depth > 0 && depth < threshold {
                            mask[y][x] = true
                            objectPixels += 1
                        }
                    }
                }
                
                // Score this mask based on compactness and size
                let compactness = calculateMaskCompactness(mask)
                let sizeScore = Double(objectPixels)
                let totalScore = sizeScore * compactness
                
                print("🔧 Threshold \(String(format: "%.3f", threshold)): \(objectPixels) pixels, compactness: \(String(format: "%.3f", compactness)), score: \(String(format: "%.1f", totalScore))")
                
                if totalScore > bestScore {
                    bestScore = totalScore
                    bestMask = mask
                }
            }
            
            return bestMask ?? Array(repeating: Array(repeating: false, count: width), count: height)
        }
        
        // MARK: - Mask Compactness Calculation
        private func calculateMaskCompactness(_ mask: [[Bool]]) -> Double {
            let height = mask.count
            let width = mask[0].count
            
            var objectPixels = 0
            var minX = width, maxX = 0
            var minY = height, maxY = 0
            
            for y in 0..<height {
                for x in 0..<width {
                    if mask[y][x] {
                        objectPixels += 1
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                    }
                }
            }
            
            guard objectPixels > 0 else { return 0.0 }
            
            let boundingBoxArea = (maxX - minX + 1) * (maxY - minY + 1)
            let compactness = Double(objectPixels) / Double(boundingBoxArea)
            
            return compactness
        }
        
        // MARK: - Improved Morphological Cleaning
        private func improvedMorphologicalCleaning(_ mask: [[Bool]], stats: (minDepth: Float, maxDepth: Float, meanDepth: Float, medianDepth: Float, stdDev: Float)) -> [[Bool]] {
            
            // Adaptive kernel sizes based on image resolution
            let height = mask.count
            let width = mask[0].count
            let imageSize = sqrt(Double(width * height))
            
            let smallKernel = max(1, Int(imageSize / 200)) // ~2-3 for typical images
            let mediumKernel = max(2, Int(imageSize / 100)) // ~4-6 for typical images
            
            print("🔧 Morphological cleaning with kernels: \(smallKernel), \(mediumKernel)")
            
            // Step 1: Remove small noise
            var cleaned = morphologicalErosion(mask, kernelSize: smallKernel)
            
            // Step 2: Fill gaps
            cleaned = morphologicalDilation(cleaned, kernelSize: mediumKernel)
            
            // Step 3: Smooth boundaries
            cleaned = morphologicalErosion(cleaned, kernelSize: smallKernel)
            
            return cleaned
        }
        
        // MARK: - PROPER Moore Neighborhood Contour Tracing
        private func mooreNeighborhoodContourTracing(_ mask: [[Bool]]) -> [CGPoint] {
            let height = mask.count
            let width = mask[0].count
            
            // Find starting point (first object pixel from top-left)
            var startPoint: (x: Int, y: Int)?
            
            outerSearch: for y in 0..<height {
                for x in 0..<width {
                    if mask[y][x] {
                        startPoint = (x, y)
                        break outerSearch
                    }
                }
            }
            
            guard let start = startPoint else { return [] }
            
            // Moore neighborhood directions (8-connected)
            // Starting from right and going clockwise
            let directions = [
                (1, 0),   // 0: Right
                (1, 1),   // 1: Bottom-right
                (0, 1),   // 2: Bottom
                (-1, 1),  // 3: Bottom-left
                (-1, 0),  // 4: Left
                (-1, -1), // 5: Top-left
                (0, -1),  // 6: Top
                (1, -1)   // 7: Top-right
            ]
            
            var contour: [CGPoint] = []
            var current = start
            var direction = 6 // Start looking upward (will wrap to find first boundary)
            
            let maxIterations = width * height // Safety limit
            var iterations = 0
            
            repeat {
                contour.append(CGPoint(x: current.x, y: current.y))
                
                // Look for next boundary pixel using Moore neighborhood
                var found = false
                var searchDirection = (direction + 6) % 8 // Start 90° counterclockwise from last direction
                
                for _ in 0..<8 {
                    let (dx, dy) = directions[searchDirection]
                    let nextX = current.x + dx
                    let nextY = current.y + dy
                    
                    // Check bounds and if pixel is part of object
                    if nextX >= 0 && nextX < width && nextY >= 0 && nextY < height && mask[nextY][nextX] {
                        // Found next boundary pixel
                        current = (nextX, nextY)
                        direction = searchDirection
                        found = true
                        break
                    }
                    
                    searchDirection = (searchDirection + 1) % 8
                }
                
                if !found {
                    print("⚠️ Moore tracing lost boundary at (\(current.x), \(current.y))")
                    break
                }
                
                iterations += 1
                
            } while (current.x != start.x || current.y != start.y) && iterations < maxIterations
            
            if iterations >= maxIterations {
                print("⚠️ Moore tracing hit iteration limit")
            }
            
            print("🔧 Moore tracing completed in \(iterations) iterations")
            return contour
        }
        
        // MARK: - Fallback Contour Extraction
        private func fallbackContourExtraction(_ mask: [[Bool]], originalWidth: Int, originalHeight: Int) -> [CGPoint]? {
            print("🔧 Using fallback contour extraction")
            
            // Simple but reliable boundary pixel extraction
            let height = mask.count
            let width = mask[0].count
            var boundaryPixels: [CGPoint] = []
            
            for y in 1..<(height-1) {
                for x in 1..<(width-1) {
                    if mask[y][x] {
                        // Check if it's a boundary pixel
                        var isBoundary = false
                        for dy in -1...1 {
                            for dx in -1...1 {
                                let nx = x + dx
                                let ny = y + dy
                                if nx >= 0 && nx < width && ny >= 0 && ny < height && !mask[ny][nx] {
                                    isBoundary = true
                                    break
                                }
                            }
                            if isBoundary { break }
                        }
                        
                        if isBoundary {
                            boundaryPixels.append(CGPoint(x: x, y: y))
                        }
                    }
                }
            }
            
            guard !boundaryPixels.isEmpty else { return nil }
            
            print("🔧 Fallback found \(boundaryPixels.count) boundary pixels")
            
            // Create a more conservative outline using convex hull
            let hull = convexHull(boundaryPixels)
            let refined = conservativeContourRefinement(hull, targetPoints: 150)
            
            return convertToDisplayCoordinates(refined, originalWidth: originalWidth, originalHeight: originalHeight)
        }
        
        // MARK: - Convex Hull for Fallback
        private func convexHull(_ points: [CGPoint]) -> [CGPoint] {
            guard points.count > 3 else { return points }
            
            let sortedPoints = points.sorted { p1, p2 in
                if p1.x != p2.x { return p1.x < p2.x }
                return p1.y < p2.y
            }
            
            func cross(_ O: CGPoint, _ A: CGPoint, _ B: CGPoint) -> CGFloat {
                return (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)
            }
            
            // Build lower hull
            var hull: [CGPoint] = []
            for p in sortedPoints {
                while hull.count >= 2 && cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 {
                    hull.removeLast()
                }
                hull.append(p)
            }
            
            // Build upper hull
            let t = hull.count + 1
            for p in sortedPoints.reversed() {
                while hull.count >= t && cross(hull[hull.count-2], hull[hull.count-1], p) <= 0 {
                    hull.removeLast()
                }
                hull.append(p)
            }
            
            hull.removeLast() // Remove duplicate point
            return hull
        }
        
        // MARK: - Conservative Contour Refinement
        private func conservativeContourRefinement(_ contour: [CGPoint], targetPoints: Int) -> [CGPoint] {
            guard contour.count > targetPoints else { return contour }
            
            print("🔧 Conservative refinement: \(contour.count) → target: \(targetPoints)")
            
            // Very light smoothing first (preserve 95% of detail)
            var smoothed = contour
            if contour.count > 50 {
                smoothed = []
                for i in 0..<contour.count {
                    let prev = contour[(i - 1 + contour.count) % contour.count]
                    let curr = contour[i]
                    let next = contour[(i + 1) % contour.count]
                    
                    // Very light averaging (90% current point, 5% each neighbor)
                    let avgX = curr.x * 0.9 + prev.x * 0.05 + next.x * 0.05
                    let avgY = curr.y * 0.9 + prev.y * 0.05 + next.y * 0.05
                    
                    smoothed.append(CGPoint(x: avgX, y: avgY))
                }
            }
            
            // Conservative Douglas-Peucker
            let epsilon = CGFloat(0.3) // Much more conservative
            let simplified = douglasPeuckerSimplify(smoothed, epsilon: epsilon)
            
            print("🔧 Final refinement: \(contour.count) → \(smoothed.count) → \(simplified.count)")
            
            return simplified
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
    @State private var showVoxels: Bool = true
    @State private var voxelNode: SCNNode?
    
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
                                Text("Volume: \(String(format: "%.2f", totalVolume * 1_000_000)) cm³") // calibration factor would go here
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
                    
                    // Voxel toggle
                    VStack {
                        Toggle("Voxels", isOn: $showVoxels)
                            .foregroundColor(.white)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            .onChange(of: showVoxels) { _, newValue in
                                toggleVoxelVisibility(show: newValue)
                            }
                    }
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
    
    private func toggleVoxelVisibility(show: Bool) {
        guard let voxelNode = voxelNode else { return }
        
        if show {
            scene?.rootNode.addChildNode(voxelNode)
        } else {
            voxelNode.removeFromParentNode()
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
        let voxelNodeInstance = SCNNode(geometry: voxelGeometry)
        
        // Update volume information
        DispatchQueue.main.async {
            self.totalVolume = volumeInfo.totalVolume
            self.voxelCount = volumeInfo.voxelCount
            self.voxelSize = volumeInfo.voxelSize
            self.voxelNode = voxelNodeInstance
        }
        
        scene.rootNode.addChildNode(pointCloudNode)
        
        // Only add voxel node if showVoxels is true
        if showVoxels {
            scene.rootNode.addChildNode(voxelNodeInstance)
        }
        
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
            print("No camera intrinsics available")
            return []
        }
        
        print("=== 3D CONVERSION DIAGNOSTICS ===")
        print("Camera intrinsics from CSV:")
        print("  fx=\(intrinsics.fx), fy=\(intrinsics.fy)")
        print("  cx=\(intrinsics.cx), cy=\(intrinsics.cy)")
        print("  Reference dimensions: \(intrinsics.width) x \(intrinsics.height)")
        
        // CORRECTION: Scale intrinsics from 4032x2268 to 640x360 resolution
        let resolutionScaleX: Float = 640.0 / 4032.0   // = 0.1587
        let resolutionScaleY: Float = 360.0 / 2268.0   // = 0.1587
        
        print("Hardcoded scaling assumptions:")
        print("  From 4032x2268 to 640x360")
        print("  ScaleX: \(resolutionScaleX), ScaleY: \(resolutionScaleY)")
        
        // Check if the CSV reference dimensions match our hardcoded assumptions
        let expectedOriginalWidth: Float = 4032.0
        let expectedOriginalHeight: Float = 2268.0
        let expectedScaledWidth: Float = 640.0
        let expectedScaledHeight: Float = 360.0
        
        print("Assumption validation:")
        print("  CSV ref width matches 4032? \(abs(intrinsics.width - expectedOriginalWidth) < 1.0)")
        print("  CSV ref height matches 2268? \(abs(intrinsics.height - expectedOriginalHeight) < 1.0)")
        
        let correctedFx = intrinsics.fx * resolutionScaleX
        let correctedFy = intrinsics.fy * resolutionScaleY
        let correctedCx = intrinsics.cx * resolutionScaleX
        let correctedCy = intrinsics.cy * resolutionScaleY
        
        print("Resolution-Corrected Intrinsics:")
        print("  Original: fx=\(intrinsics.fx), fy=\(intrinsics.fy)")
        print("  Corrected: fx=\(correctedFx), fy=\(correctedFy)")
        print("  Scale factors: \(resolutionScaleX)x")
        
        // Calculate average depth from all points in the captured image
        let totalDepth = points.reduce(0.0) { $0 + $1.depth }
        let averageDepth = points.isEmpty ? 0.5 : totalDepth / Float(points.count)
        
        print("Calculated average depth: \(averageDepth) meters")
        
        // Sample a few points to show the conversion process
        print("Sample point conversions (first 3 points):")
        
        for (index, point) in points.enumerated() {
            if index >= 3 { break }
            
            let pixelX = point.x
            let pixelY = point.y
            let depthInMeters = point.depth
            
            let realWorldX = (pixelX - correctedCx) * averageDepth / correctedFx // Using averageDepth instead of 0.5
            let realWorldY = (pixelY - correctedCy) * averageDepth / correctedFy // Using averageDepth instead of 0.5
            let realWorldZ = depthInMeters
            
            print("  Point \(index): pixel(\(pixelX), \(pixelY)) depth=\(depthInMeters)m -> world(\(realWorldX), \(realWorldY), \(realWorldZ))")
            
            measurementPoints3D.append(SCNVector3(realWorldX, realWorldY, realWorldZ))
        }
        
        // Process remaining points
        for point in points.dropFirst(3) {
            let pixelX = point.x
            let pixelY = point.y
            let depthInMeters = point.depth
            
            let realWorldX = (pixelX - correctedCx) * averageDepth / correctedFx // Using averageDepth instead of 0.5
            let realWorldY = (pixelY - correctedCy) * averageDepth / correctedFy // Using averageDepth instead of 0.5
            let realWorldZ = depthInMeters
            
            measurementPoints3D.append(SCNVector3(realWorldX, realWorldY, realWorldZ))
        }
        
        // Center the point cloud
        let bbox = calculateBoundingBox(measurementPoints3D)
        print("Bounding box BEFORE centering:")
        print("  Min: (\(bbox.min.x), \(bbox.min.y), \(bbox.min.z))")
        print("  Max: (\(bbox.max.x), \(bbox.max.y), \(bbox.max.z))")
        print("  Size: (\((bbox.max.x - bbox.min.x) * 100)cm, \((bbox.max.y - bbox.min.y) * 100)cm, \((bbox.max.z - bbox.min.z) * 100)cm)")
        
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
        
        let finalBbox = calculateBoundingBox(measurementPoints3D)
        let finalWidth = (finalBbox.max.x - finalBbox.min.x) * 100
        let finalHeight = (finalBbox.max.y - finalBbox.min.y) * 100
        let finalDepth = (finalBbox.max.z - finalBbox.min.z) * 100
        
        print("FINAL DIMENSIONS (after centering):")
        print("  Width: \(finalWidth)cm")
        print("  Height: \(finalHeight)cm")
        print("  Depth: \(finalDepth)cm")
        print("  Aspect ratios: W/H=\(finalWidth/finalHeight), W/D=\(finalWidth/finalDepth), H/D=\(finalHeight/finalDepth)")
        print("==================================")
        
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
            let invertedDepth = 1.0 - normalizedDepth  // Invert: closer = high value, farther = low value
            let voxelColor = depthToColor(invertedDepth)  // Pass inverted depth
            
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
            let invertedDepth = 1.0 - normalizedDepth  // Invert: closer = high value, farther = low value
            let color = depthToColor(invertedDepth)  // Pass inverted depth
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
