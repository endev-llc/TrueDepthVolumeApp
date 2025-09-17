//
//  OverlayView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import SwiftUI
import UIKit

// MARK: - Enhanced Overlay View with Drawing
struct OverlayView: View {
    let depthImage: UIImage
    let photo: UIImage? // Made optional for uploaded CSV files
    let cameraManager: CameraManager
    let onDismiss: () -> Void
    @State private var drawingId = UUID()
    
    @State private var photoOpacity: Double = 0.7
    @State private var showingDepthOnly = false
    @State private var isDrawingMode = false
    @State private var drawnPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var imageFrame: CGRect = .zero
    
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
                        // Only show depth/photo toggle if photo exists
                        if photo != nil {
                            Button(showingDepthOnly ? "Show Both" : "Depth Only") {
                                showingDepthOnly.toggle()
                            }
                            .foregroundColor(.white)
                            .padding()
                        }
                        
                        Button("Draw Outline") {
                            isDrawingMode = true
                            drawnPath = []
                        }
                        .foregroundColor(.cyan)
                        .padding()
                    } else {
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
                    }
                }
                
                // Opacity slider (only show if photo exists and not depth only)
                if !showingDepthOnly && photo != nil {
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
                        
                        // Photo (top layer with opacity) - only show if exists and not depth only
                        if !showingDepthOnly, let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // Always include DrawingOverlay to maintain consistent positioning
                        DrawingOverlay(
                            path: $drawnPath,
                            isDrawing: $isDrawing,
                            frameSize: geometry.size,
                            imageFrame: imageFrame
                        )
                        .id(drawingId) // Add this line
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