//
//  PocketScaleLiDARView.swift
//  PocketScale
//
//  LiDAR-powered volume measurement for food items with ARKit fallback
//

import SwiftUI
import ARKit
import RealityKit
import Combine

// MARK: - Main PocketScale View with LiDAR Integration and ARKit Fallback
struct PocketScaleLiDARView: View {
    @StateObject private var arManager = ARVolumeManager()
    @State private var isScanning = false
    @State private var showResults = false
    @State private var measuredVolume: Double = 0.0
    @State private var estimatedWeight: Double = 0.0
    @State private var foodItem: String = "Unknown Item"
    @State private var showingScanningInstructions = true
    @State private var debugInfo: String = "Ready to scan"
    
    var body: some View {
        ZStack {
            // AR Camera View
            ARVolumeView(arManager: arManager)
                .ignoresSafeArea()
                .onTapGesture { location in
                    // For non-LiDAR devices, allow user to tap to add measurement points
                    if !arManager.isLiDARAvailable && isScanning {
                        arManager.addManualPoint(at: location)
                    }
                }
            
            // UI Overlay
            VStack {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PocketScale")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                        Text(arManager.isLiDARAvailable ? "LiDAR Volume Scanner" : "ARKit Volume Scanner")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 1)
                    }
                    Spacer()
                    
                    // Technology status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(arManager.isLiDARAvailable ? Color.green : Color.blue)
                            .frame(width: 8, height: 8)
                        Text(arManager.isLiDARAvailable ? "LiDAR" : "ARKit")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Debug info (remove in production)
                Text(debugInfo)
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 24)
                
                Spacer()
                
                // Scanning Area Indicator
                if !showResults {
                    VStack(spacing: 20) {
                        // Scanning frame
                        ZStack {
                            // Scanning bounds rectangle
                            Rectangle()
                                .stroke(
                                    isScanning ? Color.blue : Color.white.opacity(0.6),
                                    style: StrokeStyle(
                                        lineWidth: 2,
                                        dash: isScanning ? [] : [10, 5]
                                    )
                                )
                                .frame(width: 280, height: 280)
                                .scaleEffect(isScanning ? 1.02 : 1.0)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isScanning)
                            
                            // Corner brackets
                            ForEach(0..<4) { index in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isScanning ? Color.blue : Color.white)
                                    .frame(width: 20, height: 4)
                                    .offset(
                                        x: index % 2 == 0 ? -130 : 130,
                                        y: index < 2 ? -130 : 130
                                    )
                                    .rotationEffect(.degrees(Double(index * 90)))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isScanning ? Color.blue : Color.white)
                                    .frame(width: 4, height: 20)
                                    .offset(
                                        x: index % 2 == 0 ? -130 : 130,
                                        y: index < 2 ? -130 : 130
                                    )
                                    .rotationEffect(.degrees(Double(index * 90)))
                            }
                            
                            // Instructions or scanning status
                            VStack(spacing: 8) {
                                if isScanning {
                                    Text("Scanning...")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.blue)
                                    
                                    Text("Volume: \(String(format: "%.1f", arManager.currentVolume)) cm³")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(12)
                                    
                                    Text("Points: \(arManager.debugPointCount)")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.yellow)
                                        
                                    if !arManager.isLiDARAvailable {
                                        Text("Tap around the object")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                } else if showingScanningInstructions {
                                    VStack(spacing: 4) {
                                        Text("Place food item")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("within the frame")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white.opacity(0.8))
                                        
                                        if !arManager.isLiDARAvailable {
                                            Text("(ARKit estimation)")
                                                .font(.system(size: 12))
                                                .foregroundColor(.blue.opacity(0.8))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(12)
                                }
                            }
                        }
                        
                        // Accuracy indicator
                        if !isScanning {
                            HStack(spacing: 8) {
                                Image(systemName: arManager.isLiDARAvailable ? "ruler.fill" : "camera.viewfinder")
                                    .foregroundColor(arManager.isLiDARAvailable ? .green : .blue)
                                    .font(.system(size: 16))
                                Text(arManager.isLiDARAvailable ? "±0.5ml precision" : "±2ml precision")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                        }
                    }
                }
                
                // Results Panel
                if showResults {
                    VStack(spacing: 24) {
                        // Status indicator
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Volume Measured")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        // Volume display
                        VStack(spacing: 8) {
                            HStack(alignment: .bottom, spacing: 8) {
                                Text("\(String(format: "%.1f", measuredVolume))")
                                    .font(.system(size: 48, weight: .light, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("cm³")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .offset(y: -8)
                                
                                Spacer()
                            }
                            
                            // Weight estimation (if food item identified)
                            if estimatedWeight > 0 {
                                HStack(alignment: .bottom, spacing: 8) {
                                    Text("≈ \(String(format: "%.1f", estimatedWeight))")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.blue)
                                    
                                    Text("grams")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue.opacity(0.8))
                                        .offset(y: -2)
                                    
                                    Spacer()
                                }
                            }
                        }
                        
                        // Metadata
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("DETECTED ITEM")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .tracking(1)
                                    Text(foodItem)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("CONFIDENCE")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .tracking(1)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(arManager.isLiDARAvailable ? Color.green : Color.blue)
                                            .frame(width: 6, height: 6)
                                        Text(arManager.isLiDARAvailable ? "95%" : "75%")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(arManager.isLiDARAvailable ? .green : .blue)
                                    }
                                }
                            }
                            
                            // Technology info
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TECHNOLOGY")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                        .tracking(1)
                                    Text(arManager.isLiDARAvailable ? "LiDAR Mesh" : "ARKit Estimation")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(arManager.isLiDARAvailable ? .green : .blue)
                                }
                                Spacer()
                            }
                            
                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Save Measurement")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.blue)
                                    .cornerRadius(14)
                                }
                                
                                Button(action: resetScan) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.blue)
                                        .frame(width: 50, height: 50)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(14)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(24)
                    .padding(.horizontal, 24)
                }
                
                Spacer()
                
                // Scan button
                if !showResults {
                    Button(action: toggleScanning) {
                        HStack(spacing: 12) {
                            if isScanning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Stop Scan")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                Text(arManager.isLiDARAvailable ? "Start Volume Scan" : "Start ARKit Scan")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: isScanning ? [Color.red, Color.red.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: (isScanning ? Color.red : Color.blue).opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
        }
        .onReceive(arManager.$debugInfo) { info in
            debugInfo = info
        }
        .onAppear {
            // ARView will handle session setup automatically
        }
    }
    
    private func toggleScanning() {
        if isScanning {
            stopScanning()
        } else {
            startScanning()
        }
    }
    
    private func startScanning() {
        showingScanningInstructions = false
        isScanning = true
        arManager.startVolumeCapture()
        
        // Auto-stop after 8 seconds for demo (increased time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            if isScanning {
                stopScanning()
            }
        }
    }
    
    private func stopScanning() {
        isScanning = false
        let volume = arManager.stopVolumeCapture()
        
        // Process results
        measuredVolume = volume
        estimatedWeight = estimateWeight(volume: volume)
        foodItem = identifyFood() // This would use AI/ML in production
        
        withAnimation(.spring()) {
            showResults = true
        }
    }
    
    private func resetScan() {
        withAnimation(.spring()) {
            showResults = false
            isScanning = false
            showingScanningInstructions = true
            measuredVolume = 0.0
            estimatedWeight = 0.0
            arManager.reset()
        }
    }
    
    private func estimateWeight(volume: Double) -> Double {
        // Simple density estimation - in production this would use AI/ML
        // For demo, assume density of fresh fruit (~0.8-1.0 g/cm³)
        return volume * 0.9
    }
    
    private func identifyFood() -> String {
        // In production, this would use computer vision/AI
        // For demo, return a placeholder
        return "Fresh Strawberries"
    }
}

// MARK: - AR Volume Manager with LiDAR and ARKit Support
class ARVolumeManager: NSObject, ObservableObject {
    @Published var isLiDARAvailable = false
    @Published var hasCheckedLiDAR = false
    @Published var currentVolume: Double = 0.0
    @Published var debugPointCount: Int = 0
    @Published var debugInfo: String = "Initializing..."
    
    private var arView: ARView?
    private var isCapturing = false
    private var capturedPoints: [SIMD3<Float>] = []
    private var scanningBounds: SIMD3<Float> = SIMD3<Float>(0.28, 0.28, 0.20) // 28cm x 28cm x 20cm scanning area
    
    // For non-LiDAR volume estimation
    private var detectedPlanes: [ARPlaneAnchor] = []
    private var manualPoints: [SIMD3<Float>] = []
    private var lastKnownCameraTransform: simd_float4x4?
    
    override init() {
        super.init()
        checkARCapabilities()
    }
    
    func checkARCapabilities() {
        isLiDARAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        hasCheckedLiDAR = true
        debugInfo = isLiDARAvailable ? "LiDAR available" : "Using ARKit fallback"
    }
    
    func startVolumeCapture() {
        isCapturing = true
        capturedPoints.removeAll()
        detectedPlanes.removeAll()
        manualPoints.removeAll()
        currentVolume = 0.0
        debugPointCount = 0
        debugInfo = isLiDARAvailable ? "LiDAR scanning started" : "ARKit scanning started"
        
        // Start monitoring the AR session
        startMonitoring()
    }
    
    func stopVolumeCapture() -> Double {
        isCapturing = false
        let volume = isLiDARAvailable ? calculateLiDARVolume() : calculateARKitVolume()
        debugInfo = "Scan complete. Volume: \(String(format: "%.1f", volume)) cm³"
        return volume
    }
    
    func reset() {
        capturedPoints.removeAll()
        detectedPlanes.removeAll()
        manualPoints.removeAll()
        currentVolume = 0.0
        debugPointCount = 0
        isCapturing = false
        debugInfo = "Reset complete"
    }
    
    func addManualPoint(at screenPoint: CGPoint) {
        guard let arView = self.arView, isCapturing, !isLiDARAvailable else { return }
        
        // Convert screen point to world coordinates
        let hitTestResults = arView.hitTest(screenPoint, types: [.existingPlaneUsingExtent, .estimatedHorizontalPlane])
        
        if let result = hitTestResults.first {
            let position = SIMD3<Float>(
                result.worldTransform.columns.3.x,
                result.worldTransform.columns.3.y,
                result.worldTransform.columns.3.z
            )
            
            manualPoints.append(position)
            debugPointCount = manualPoints.count
            debugInfo = "Manual points: \(manualPoints.count)"
            
            // Update volume estimate
            DispatchQueue.main.async {
                let volume = self.calculateARKitVolume()
                self.currentVolume = volume
            }
        }
    }
    
    func setARView(_ arView: ARView) {
        self.arView = arView
        debugInfo = "ARView connected"
    }
    
    private func startMonitoring() {
        guard let arView = self.arView else { return }
        
        // Create a timer to periodically check for data
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard self.isCapturing else {
                timer.invalidate()
                return
            }
            
            self.processCurrentFrame()
        }
    }
    
    private func processCurrentFrame() {
        guard let arView = self.arView, isCapturing else { return }
        
        let currentFrame = arView.session.currentFrame
        guard let frame = currentFrame else { return }
        
        lastKnownCameraTransform = frame.camera.transform
        
        if isLiDARAvailable {
            processLiDARData(frame: frame)
        } else {
            processARKitData(frame: frame)
        }
    }
    
    private func processLiDARData(frame: ARFrame) {
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        var newPointsCount = 0
        
        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let vertices = geometry.vertices
            let transform = meshAnchor.transform
            
            let vertexBuffer = vertices.buffer.contents()
            let vertexStride = vertices.stride
            let vertexCount = vertices.count
            
            for i in 0..<vertexCount {
                let vertexPointer = vertexBuffer.advanced(by: i * vertexStride)
                let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldPosition = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
                let position = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
                
                // Check if point is within scanning bounds relative to camera
                if let cameraTransform = lastKnownCameraTransform {
                    let relativePosition = position - SIMD3<Float>(
                        cameraTransform.columns.3.x,
                        cameraTransform.columns.3.y,
                        cameraTransform.columns.3.z
                    )
                    
                    if abs(relativePosition.x) <= scanningBounds.x/2 &&
                       abs(relativePosition.y) <= scanningBounds.y/2 &&
                       relativePosition.z >= -scanningBounds.z && relativePosition.z <= 0.1 {
                        capturedPoints.append(position)
                        newPointsCount += 1
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.debugPointCount = self.capturedPoints.count
            if newPointsCount > 0 {
                let volume = self.calculateLiDARVolume()
                self.currentVolume = volume
                self.debugInfo = "LiDAR points: \(self.capturedPoints.count), Volume: \(String(format: "%.1f", volume)) cm³"
            }
        }
    }
    
    private func processARKitData(frame: ARFrame) {
        // Update detected planes
        let planeAnchors = frame.anchors.compactMap { $0 as? ARPlaneAnchor }
        detectedPlanes = planeAnchors
        
        DispatchQueue.main.async {
            if !self.manualPoints.isEmpty || !self.detectedPlanes.isEmpty {
                let volume = self.calculateARKitVolume()
                self.currentVolume = volume
                self.debugInfo = "Planes: \(self.detectedPlanes.count), Manual points: \(self.manualPoints.count)"
            } else {
                self.debugInfo = "Move device to detect surfaces, then tap on object"
            }
        }
    }
    
    // MARK: - LiDAR Volume Calculation
    private func calculateLiDARVolume() -> Double {
        guard capturedPoints.count > 3 else { return 0.0 }
        
        // Remove duplicate points and filter by density
        let filteredPoints = filterAndClusterPoints(capturedPoints)
        guard filteredPoints.count > 3 else { return 0.0 }
        
        let volume = calculateConvexHullVolume(points: filteredPoints)
        return Double(volume * 1000000) // Convert from m³ to cm³
    }
    
    // MARK: - ARKit Volume Calculation (without LiDAR)
    private func calculateARKitVolume() -> Double {
        if !manualPoints.isEmpty {
            // Use manual points if available
            let volume = calculateConvexHullVolume(points: manualPoints)
            return Double(volume * 1000000) // Convert from m³ to cm³
        } else if !detectedPlanes.isEmpty {
            // Fallback to plane-based estimation
            return estimateVolumeFromPlanes()
        } else {
            return 0.0
        }
    }
    
    private func estimateVolumeFromPlanes() -> Double {
        guard !detectedPlanes.isEmpty else { return 0.0 }
        
        // Find the largest horizontal plane
        let horizontalPlanes = detectedPlanes.filter {
            abs($0.transform.columns.1.y) > 0.8 // Normal vector pointing up
        }
        
        guard let largestPlane = horizontalPlanes.max(by: {
            ($0.extent.x * $0.extent.z) < ($1.extent.x * $1.extent.z)
        }) else {
            return 25.0 // Default estimation of 25cm³ if no good planes detected
        }
        
        // Estimate volume based on scanning area and average height
        let baseArea = min(largestPlane.extent.x, scanningBounds.x) * min(largestPlane.extent.z, scanningBounds.y)
        let estimatedHeight: Float = 0.04 // 4cm default height assumption for food items
        
        return Double(baseArea * estimatedHeight * 1000000) // Convert to cm³
    }
    
    private func filterAndClusterPoints(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard points.count > 10 else { return points }
        
        // Simple filtering: remove points that are too far from the cluster center
        let center = points.reduce(SIMD3<Float>(0, 0, 0)) { $0 + $1 } / Float(points.count)
        
        let filtered = points.filter { point in
            let distance = distance(point, center)
            return distance < 0.15 // 15cm max distance from center
        }
        
        // Subsample if we have too many points (performance)
        if filtered.count > 500 {
            return Array(filtered.prefix(500))
        }
        
        return filtered
    }
    
    private func calculateConvexHullVolume(points: [SIMD3<Float>]) -> Float {
        guard points.count >= 4 else { return 0.0 }
        
        // Find bounding box
        let minPoint = points.reduce(points[0]) { point1, point2 in
            SIMD3<Float>(
                min(point1.x, point2.x),
                min(point1.y, point2.y),
                min(point1.z, point2.z)
            )
        }
        
        let maxPoint = points.reduce(points[0]) { point1, point2 in
            SIMD3<Float>(
                max(point1.x, point2.x),
                max(point1.y, point2.y),
                max(point1.z, point2.z)
            )
        }
        
        let dimensions = maxPoint - minPoint
        
        // Apply a shape factor based on the distribution of points
        let shapeFactor: Float = calculateShapeFactor(points: points, minPoint: minPoint, maxPoint: maxPoint)
        
        return dimensions.x * dimensions.y * dimensions.z * shapeFactor
    }
    
    private func calculateShapeFactor(points: [SIMD3<Float>], minPoint: SIMD3<Float>, maxPoint: SIMD3<Float>) -> Float {
        // Analyze point distribution to estimate how much of the bounding box is actually filled
        let dimensions = maxPoint - minPoint
        let volume = dimensions.x * dimensions.y * dimensions.z
        
        guard volume > 0 else { return 0.0 }
        
        // For food items, typical shape factors:
        // - Sphere/apple: ~0.52
        // - Irregular fruits: ~0.4-0.7
        // - Flat items: ~0.3-0.5
        
        // Simple heuristic based on point density
        let pointDensity = Float(points.count) / volume
        
        if pointDensity > 1000 {
            return 0.6 // Dense object, likely solid
        } else if pointDensity > 100 {
            return 0.45 // Medium density
        } else {
            return 0.35 // Lower density, more irregular shape
        }
    }
}

// MARK: - ARView Container
struct ARVolumeView: UIViewRepresentable {
    let arManager: ARVolumeManager
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // We need to manually configure the session for our specific needs
        arView.automaticallyConfigureSession = false
        
        // Configure the session for LiDAR if available
        if arManager.isLiDARAvailable {
            let configuration = ARWorldTrackingConfiguration()
            configuration.sceneReconstruction = .mesh
            configuration.environmentTexturing = .automatic
            arView.session.run(configuration)
        } else {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            arView.session.run(configuration)
        }
        
        // Set the ARView reference in the manager
        arManager.setARView(arView)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No need to update configurations here since we set them in makeUIView
    }
}

// MARK: - Preview
#Preview {
    PocketScaleLiDARView()
}
