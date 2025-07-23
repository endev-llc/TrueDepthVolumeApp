//
//  ARDistanceMeasurementView.swift
//  landing-page-mockups
//
//  Created by Jake Adams on 6/28/25.
//


import SwiftUI
import ARKit
import RealityKit

// MARK: - Distance Measurement View
struct ARDistanceMeasurementView: View {
    @StateObject private var distanceManager = ARDistanceManager()
    @State private var measuredDistance: Double = 0.0
    @State private var isMeasuring = false
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARDistanceView(distanceManager: distanceManager)
                .ignoresSafeArea()
                .onTapGesture { location in
                    measureDistance(at: location)
                }
            
            // UI Overlay
            VStack {
                // Header with current distance
                HStack {
                    VStack(alignment: .leading) {
                        Text("Distance Meter")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        
                        Text(distanceManager.isLiDARAvailable ? "LiDAR Precision" : "ARKit Mode")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Distance display
                    VStack(alignment: .trailing) {
                        Text("\(String(format: "%.1f", measuredDistance)) cm")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                        
                        Text("±\(distanceManager.isLiDARAvailable ? "1" : "3")cm accuracy")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                // Crosshair for targeting
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 50, height: 50)
                    )
                    .scaleEffect(isMeasuring ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isMeasuring)
                
                Spacer()
                
                // Instructions
                VStack(spacing: 12) {
                    Text("Tap to measure distance")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Point center of screen at object")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 16) {
                        Label("Best range: 2-10 feet", systemImage: "ruler")
                        Label("Good lighting needed", systemImage: "sun.max")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
        .onReceive(distanceManager.$lastMeasuredDistance) { distance in
            measuredDistance = distance
        }
    }
    
    private func measureDistance(at point: CGPoint) {
        isMeasuring = true
        distanceManager.measureDistance(at: point)
        
        // Reset animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isMeasuring = false
        }
    }
}

// MARK: - Distance Manager
class ARDistanceManager: NSObject, ObservableObject {
    @Published var isLiDARAvailable = false
    @Published var lastMeasuredDistance: Double = 0.0
    
    private var arView: ARView?
    
    override init() {
        super.init()
        checkLiDARAvailability()
    }
    
    func checkLiDARAvailability() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
    
    func setARView(_ arView: ARView) {
        self.arView = arView
    }
    
    // MARK: - Method 1: Hit Test Distance Measurement (Most Common)
    func measureDistance(at screenPoint: CGPoint) {
        guard let arView = self.arView else { return }
        
        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        
        if isLiDARAvailable {
            measureDistanceWithLiDAR(at: screenCenter)
        } else {
            measureDistanceWithHitTest(at: screenCenter)
        }
    }
    
    // MARK: - LiDAR-based Distance Measurement (Most Precise)
    private func measureDistanceWithLiDAR(at point: CGPoint) {
        guard let arView = self.arView else { return }
        
        // Get current camera position
        guard let currentFrame = arView.session.currentFrame else { return }
        let cameraTransform = currentFrame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        // Check for mesh anchors (LiDAR data)
        let meshAnchors = currentFrame.anchors.compactMap { $0 as? ARMeshAnchor }
        var closestDistance: Float = Float.greatestFiniteMagnitude
        
        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices
            let transform = meshAnchor.transform
            
            // Sample vertices to find closest point in camera's direction
            let vertexBuffer = vertices.buffer.contents()
            let vertexStride = vertices.stride
            let vertexCount = min(vertices.count, 1000) // Sample for performance
            
            for i in stride(from: 0, to: vertexCount, by: 10) {
                let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
                let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldPosition = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
                let vertexPosition = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
                
                let distance = simd_distance(cameraPosition, vertexPosition)
                
                // Check if this vertex is roughly in the direction we're pointing
                let direction = normalize(vertexPosition - cameraPosition)
                let cameraForward = SIMD3<Float>(-cameraTransform.columns.2.x, -cameraTransform.columns.2.y, -cameraTransform.columns.2.z)
                let dot = simd_dot(direction, cameraForward)
                
                if dot > 0.9 && distance < closestDistance { // 0.9 = ~25 degree cone
                    closestDistance = distance
                }
            }
        }
        
        if closestDistance != Float.greatestFiniteMagnitude {
            DispatchQueue.main.async {
                self.lastMeasuredDistance = Double(closestDistance * 100) // Convert to cm
            }
        } else {
            // Fallback to hit test if no mesh data available
            measureDistanceWithHitTest(at: point)
        }
    }
    
    // MARK: - Hit Test Distance Measurement (Fallback for non-LiDAR)
    private func measureDistanceWithHitTest(at point: CGPoint) {
        guard let arView = self.arView else { return }
        
        // Perform hit test against detected planes and feature points
        let hitTestResults = arView.hitTest(
            point,
            types: [.estimatedHorizontalPlane, .existingPlaneUsingExtent, .featurePoint]
        )
        
        if let result = hitTestResults.first {
            let distance = result.distance
            
            DispatchQueue.main.async {
                self.lastMeasuredDistance = Double(distance * 100) // Convert to cm
            }
        }
    }
    
    // MARK: - Method 2: Camera-to-World Position Distance
    func measureDistanceToWorldPosition(_ worldPosition: SIMD3<Float>) -> Float {
        guard let arView = self.arView,
              let currentFrame = arView.session.currentFrame else { return 0 }
        
        let cameraTransform = currentFrame.camera.transform
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        
        return simd_distance(cameraPosition, worldPosition)
    }
    
    // MARK: - Method 3: Depth Data Distance (Front Camera with TrueDepth)
    func measureDistanceWithDepthData() -> Float? {
        guard let arView = self.arView,
              let currentFrame = arView.session.currentFrame,
              let depthData = currentFrame.smoothedSceneDepth?.depthMap else { return nil }
        
        // Get center pixel depth
        let width = CVPixelBufferGetWidth(depthData)
        let height = CVPixelBufferGetHeight(depthData)
        let centerX = width / 2
        let centerY = height / 2
        
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthData, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthData) else { return nil }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthData)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        let pixelIndex = centerY * (bytesPerRow / MemoryLayout<Float32>.size) + centerX
        let depth = buffer[pixelIndex]
        
        return depth // Distance in meters
    }
}

// MARK: - ARView Container
struct ARDistanceView: UIViewRepresentable {
    let distanceManager: ARDistanceManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure for distance measurement
        arView.automaticallyConfigureSession = false
        
        let configuration = ARWorldTrackingConfiguration()
        
        if distanceManager.isLiDARAvailable {
            // Enable LiDAR mesh reconstruction for precise measurements
            configuration.sceneReconstruction = .mesh
            configuration.environmentTexturing = .automatic
        } else {
            // Enable plane detection for hit testing
            configuration.planeDetection = [.horizontal, .vertical]
        }
        
        arView.session.run(configuration)
        distanceManager.setARView(arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Updates handled by the manager
    }
}

// MARK: - Utility Extensions
extension ARHitTestResult {
    var distance: Float {
        let position = SIMD3<Float>(
            worldTransform.columns.3.x,
            worldTransform.columns.3.y,
            worldTransform.columns.3.z
        )
        return simd_length(position)
    }
}

// MARK: - Example Usage for Measuring Between Two Points
class TwoPointDistanceMeasurer {
    private var firstPoint: SIMD3<Float>?
    private var secondPoint: SIMD3<Float>?
    
    func addPoint(_ worldPosition: SIMD3<Float>) -> Float? {
        if firstPoint == nil {
            firstPoint = worldPosition
            return nil
        } else {
            secondPoint = worldPosition
            defer { reset() }
            
            guard let first = firstPoint, let second = secondPoint else { return nil }
            return simd_distance(first, second)
        }
    }
    
    func reset() {
        firstPoint = nil
        secondPoint = nil
    }
}

// MARK: - Preview
#Preview {
    ARDistanceMeasurementView()
}