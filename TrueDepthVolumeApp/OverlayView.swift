//
//  OverlayView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import SwiftUI
import UIKit

// MARK: - Enhanced Overlay View with Auto-Segmentation
struct OverlayView: View {
    let depthImage: UIImage
    let photo: UIImage? // Made optional for uploaded CSV files
    let cameraManager: CameraManager
    let onDismiss: () -> Void
    var isRefinementMode: Bool = false
    var primaryCroppedCSV: URL? = nil
    var onRefine: ((UIImage, CGRect, CGSize) -> Void)? = nil
    
    @State private var drawingId = UUID()
    
    @State private var photoOpacity: Double = 0.7
    @State private var showingDepthOnly = false
    @State private var isDrawingMode = false
    @State private var drawnPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var imageFrame: CGRect = .zero
    
    // MobileSAM integration
    @StateObject private var samManager = MobileSAMManager()
    @State private var isAutoSegmentMode = false
    @State private var maskImage: UIImage?
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    @State private var showConfirmButton = false
    
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
                    
                    if !isDrawingMode && !isAutoSegmentMode {
                        // Show refinement option if we have a cropped photo and primary CSV
                        if isRefinementMode, let _ = primaryCroppedCSV {
                            Text("Tap food to refine")
                                .foregroundColor(.yellow)
                                .padding()
                        }
                        
                        // Only show depth/photo toggle if photo exists and not in refinement mode
                        if photo != nil && !isRefinementMode {
                            Button(showingDepthOnly ? "Show Both" : "Depth Only") {
                                showingDepthOnly.toggle()
                            }
                            .foregroundColor(.white)
                            .padding()
                        }
                        
                        if !isRefinementMode {
                            Button("Auto-Segment") {
                                startAutoSegmentation()
                            }
                            .foregroundColor(.cyan)
                            .padding()
                            
                            Button("Draw Outline") {
                                isDrawingMode = true
                                drawnPath = []
                            }
                            .foregroundColor(.orange)
                            .padding()
                        } else {
                            Button("Auto-Segment Food") {
                                startAutoSegmentation()
                            }
                            .foregroundColor(.green)
                            .padding()
                        }
                    } else if isDrawingMode {
                        Button("Clear") {
                            drawnPath = []
                            isDrawing = false
                            drawingId = UUID() // Force DrawingOverlay to recreate
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
                                cropCSVWithOutline()
                                isDrawingMode = false
                            }
                            .foregroundColor(.green)
                            .padding()
                        }
                    } else if isAutoSegmentMode {
                        Button("Cancel") {
                            cancelAutoSegmentation()
                        }
                        .foregroundColor(.white)
                        .padding()
                        
                        // Clear masks button
                        if maskImage != nil && !showConfirmButton {
                            Button("Clear") {
                                maskImage = nil
                                tapLocation = .zero
                            }
                            .foregroundColor(.red)
                            .padding()
                        }
                        
                        if showConfirmButton {
                            Button("Confirm") {
                                if isRefinementMode {
                                    applyRefinementMask()
                                } else {
                                    cropCSVWithMask()
                                }
                                cancelAutoSegmentation()
                            }
                            .foregroundColor(.green)
                            .padding()
                        }
                    }
                }
                .frame(height: 44)
                
                // Opacity slider (only show if photo exists and not depth only and not in refinement mode)
                if !showingDepthOnly && photo != nil && !isRefinementMode {
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
                
                // Image overlay with drawing and proper coordinate space
                GeometryReader { geometry in
                    ZStack {
                        // Depth image (bottom layer)
                        Image(uiImage: depthImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(
                                GeometryReader { imageGeometry in
                                    Color.clear
                                        .onAppear {
                                            updateImageFrame(imageGeometry: imageGeometry)
                                        }
                                        .onChange(of: imageGeometry.size) { _, _ in
                                            updateImageFrame(imageGeometry: imageGeometry)
                                        }
                                }
                            )
                        
                        // Photo (top layer with opacity) - only show if exists, not depth only, and not in refinement mode
                        if !showingDepthOnly && !isRefinementMode, let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // MobileSAM mask overlay (only in auto-segment mode)
                        if isAutoSegmentMode, let mask = maskImage {
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        
                        // Tap indicator for auto-segmentation
                        if isAutoSegmentMode && tapLocation != .zero {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                        
                        // Always include DrawingOverlay to maintain consistent positioning (only active in drawing mode)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if isAutoSegmentMode {
                            handleAutoSegmentTap(at: location)
                        }
                    }
                }
                .coordinateSpace(name: "overlayContainer")
                .padding()
                
                Spacer()
                
                // Info text
                Text(getInstructionText())
                    .foregroundColor(.white)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(minHeight: 60, alignment: .top)
                
                // Error message for MobileSAM
                if let errorMessage = samManager.errorMessage {
                    errorMessageView(errorMessage)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func errorMessageView(_ message: String) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.body)
            }
            .padding()
            .background(Color.red.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 1)
            )
            .cornerRadius(8)
            .padding()
        }
    }
    
    // MARK: - Helper Functions
    private func getInstructionText() -> String {
        if isDrawingMode {
            return "Draw around the object you want to isolate. Tap 'Confirm' when done."
        } else if isAutoSegmentMode {
            if !isImageEncoded {
                return "Encoding image for AI segmentation..."
            } else if maskImage == nil {
                if isRefinementMode {
                    return "Tap the food contents you want to isolate from the dish."
                } else {
                    return "Tap anywhere on the object you want to segment."
                }
            } else {
                if isRefinementMode {
                    return "Food mask applied! Tap more areas to add to mask, or tap 'Confirm' to refine the 3D model."
                } else {
                    return "AI mask applied! Tap more areas to add to mask, or tap 'Confirm' to crop depth data."
                }
            }
        } else {
            if isRefinementMode {
                return "Tap 'Auto-Segment Food' to isolate just the food contents from the dish."
            } else {
                return "Choose 'Auto-Segment' for AI-powered segmentation or 'Draw Outline' for manual selection."
            }
        }
    }
    
    private func updateImageFrame(imageGeometry: GeometryProxy) {
        // Get the actual frame of the rendered image in the container's coordinate space
        let frame = imageGeometry.frame(in: .named("overlayContainer"))
        imageFrame = frame
        imageDisplaySize = frame.size
    }
    
    // MARK: - Auto-Segmentation Functions
    private func startAutoSegmentation() {
        isAutoSegmentMode = true
        maskImage = nil
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        
        // Use photo for refinement mode, depth image otherwise
        let imageToSegment = isRefinementMode ? (photo ?? depthImage) : depthImage
        
        Task {
            let success = await samManager.encodeImage(imageToSegment)
            await MainActor.run {
                isImageEncoded = success
                if !success {
                    // If encoding failed, exit auto-segment mode
                    cancelAutoSegmentation()
                }
            }
        }
    }
    
    private func cancelAutoSegmentation() {
        isAutoSegmentMode = false
        maskImage = nil
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        samManager.currentImageEmbeddings = nil
    }
    
    private func handleAutoSegmentTap(at location: CGPoint) {
        guard isImageEncoded && !samManager.isLoading && imageFrame.contains(location) else { return }
        
        // Store the absolute tap location for the red dot indicator
        tapLocation = location
        
        // Convert to relative coordinates within the image
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    // Composite masks instead of replacing
                    self.maskImage = compositeMasks(self.maskImage, with: mask)
                    self.showConfirmButton = true
                }
            }
        }
    }
    
    // MARK: - Mask-based Cropping Function (Updated for Multiple Disconnected Regions)
    private func cropCSVWithMask() {
        guard let maskImage = maskImage else { return }
        
        // Create a custom cropping function that checks each point directly against the mask
        cameraManager.cropDepthDataWithMask(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size)
    }
    
    // MARK: - Refinement Function
    private func applyRefinementMask() {
        guard let maskImage = maskImage,
              let primaryCSV = primaryCroppedCSV else { return }
        
        onRefine?(maskImage, imageFrame, depthImage.size)
    }
    
    // MARK: - Original Drawing-based Cropping Function (preserved)
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
