//
//  DepthVisualization3DView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//  OPTIMIZED VERSION

import SwiftUI
import SceneKit
import AVFoundation

// MARK: - Performance Timer Helper
class PerformanceTimer {
    private var startTime: CFAbsoluteTime = 0
    private let label: String
    
    init(_ label: String) {
        self.label = label
        startTime = CFAbsoluteTimeGetCurrent()
    }
    
    func lap(_ message: String = "") {
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("⏱️ [\(label)] \(message): \(String(format: "%.2f", elapsed))ms")
        startTime = CFAbsoluteTimeGetCurrent()
    }
    
    static func measure<T>(_ label: String, block: () -> T) -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = block()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("⏱️ [\(label)]: \(String(format: "%.2f", elapsed))ms")
        return result
    }
}

// MARK: - 3D Depth Visualization View with Voxels (OPTIMIZED)
struct DepthVisualization3DView: View {
    let csvFileURL: URL
    let cameraManager: CameraManager
    let onDismiss: () -> Void
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    @State private var totalVolume: Double = 0.0
    @State private var voxelCount: Int = 0
    @State private var voxelSize: Float = 0.0
    @State private var refinementVolume: Double = 0.0
    @State private var refinementVoxelCount: Int = 0
    @State private var cameraIntrinsics: CameraIntrinsics? = nil
    @State private var showVoxels: Bool = true
    @State private var showPrimaryPointCloud: Bool = false
    @State private var showRefinementPointCloud: Bool = false
    @State private var voxelNode: SCNNode?
    @State private var primaryPointCloudNode: SCNNode?
    @State private var refinementPointCloudNode: SCNNode?
    @State private var bottomSurfaceNode: SCNNode?
    @State private var boundingBoxNode: SCNNode?
    @State private var showBoundingBox: Bool = true
    @State private var showPlaneVisualization: Bool = true
    @State private var planeVisualizationNode: SCNNode?
    
    // MARK: - State for Cropping Functionality
    @State private var showCropButton: Bool = false
    @State private var isCropped: Bool = false
    @State private var planeFloorMap: [XYKey: Int]? = nil
    @State private var planeCoefficients: (a: Float, b: Float, c: Float)? = nil
    @State private var originalFinalVoxels: Set<VoxelKey>? = nil
    @State private var minBoundingBox: SCNVector3? = nil
    @State private var maxBoundingBox: SCNVector3? = nil
    
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
                                Text("Primary: \(String(format: "%.2f", totalVolume * 1_000_000)) cm³")
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
                    
                    // Point cloud and voxel toggles
                    VStack(spacing: 8) {
                        Toggle("Primary Voxels", isOn: $showVoxels)
                            .foregroundColor(.cyan)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            .onChange(of: showVoxels) { _, newValue in
                                toggleVoxelVisibility(show: newValue)
                            }
                        
                        Toggle("Primary Points", isOn: $showPrimaryPointCloud)
                            .foregroundColor(.cyan)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            .onChange(of: showPrimaryPointCloud) { _, newValue in
                                togglePrimaryPointCloudVisibility(show: newValue)
                            }
                        
                        if refinementPointCloudNode != nil {
                            Toggle("Refined Points", isOn: $showRefinementPointCloud)
                                .foregroundColor(.green)
                                .font(.caption)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .onChange(of: showRefinementPointCloud) { _, newValue in
                                    toggleRefinementPointCloudVisibility(show: newValue)
                                }
                        }
                        
                        Toggle("Bounding Box", isOn: $showBoundingBox)
                            .foregroundColor(.yellow)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .yellow))
                            .onChange(of: showBoundingBox) { _, newValue in
                                toggleBoundingBoxVisibility(show: newValue)
                            }
                        
                        Toggle("Plane Floor", isOn: $showPlaneVisualization)
                            .foregroundColor(.pink)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .pink))
                            .onChange(of: showPlaneVisualization) { _, newValue in
                                togglePlaneVisualizationVisibility(show: newValue)
                            }
                        
                        // NEW: Crop Button
                        if showCropButton {
                            Button(isCropped ? "Show Full" : "Crop to Plane") {
                                if isCropped {
                                    resetCrop()
                                } else {
                                    cropVoxelsAbovePlane()
                                }
                            }
                            .foregroundColor(.orange)
                            .font(.caption)
                            .padding(.top, 4)
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
            // Also add bottom surface if it exists
            if let bottomSurfaceNode = bottomSurfaceNode {
                scene?.rootNode.addChildNode(bottomSurfaceNode)
            }
        } else {
            voxelNode.removeFromParentNode()
            // Also remove bottom surface if it exists
            bottomSurfaceNode?.removeFromParentNode()
        }
    }
    
    private func togglePrimaryPointCloudVisibility(show: Bool) {
        guard let primaryPointCloudNode = primaryPointCloudNode else { return }
        if show {
            scene?.rootNode.addChildNode(primaryPointCloudNode)
        } else {
            primaryPointCloudNode.removeFromParentNode()
        }
    }
    
    private func toggleRefinementPointCloudVisibility(show: Bool) {
        guard let refinementPointCloudNode = refinementPointCloudNode else { return }
        if show {
            scene?.rootNode.addChildNode(refinementPointCloudNode)
        } else {
            refinementPointCloudNode.removeFromParentNode()
        }
    }
    
    private func toggleBoundingBoxVisibility(show: Bool) {
        guard let boundingBoxNode = boundingBoxNode else { return }
        if show {
            scene?.rootNode.addChildNode(boundingBoxNode)
        } else {
            boundingBoxNode.removeFromParentNode()
        }
    }
    
    private func togglePlaneVisualizationVisibility(show: Bool) {
        guard let planeVisualizationNode = planeVisualizationNode else { return }
        if show {
            scene?.rootNode.addChildNode(planeVisualizationNode)
        } else {
            planeVisualizationNode.removeFromParentNode()
        }
    }
    
    private func loadAndCreate3DScene() {
        let overallTimer = PerformanceTimer("TOTAL 3D LOAD")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // STEP 1: Load data
                let timer1 = PerformanceTimer("Data Loading")
                let originalDepthPoints = getOriginalDepthData()
                timer1.lap("Got original depth data (\(originalDepthPoints.count) points)")
                
                let csvContent = try String(contentsOf: csvFileURL)
                let filteredDepthPoints = parseCSVContent(csvContent)
                timer1.lap("Parsed CSV (\(filteredDepthPoints.count) filtered points)")
                
                // STEP 2: Create scene
                let scene = create3DScene(originalDepthPoints: originalDepthPoints, filteredDepthPoints: filteredDepthPoints)
                
                overallTimer.lap("COMPLETE - Ready to display")
                
                DispatchQueue.main.async {
                    self.scene = scene
                    self.isLoading = false
                    self.showCropButton = true // Show crop button when loading is done
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load depth data: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func getOriginalDepthData() -> [DepthPoint] {
        if !cameraManager.uploadedCSVData.isEmpty {
            return cameraManager.uploadedCSVData
        } else if let rawDepthData = cameraManager.rawDepthData {
            return convertDepthDataToPoints(rawDepthData)
        }
        return []
    }
    
    private func convertDepthDataToPoints(_ depthData: AVDepthData) -> [DepthPoint] {
        let timer = PerformanceTimer("AVDepthData Conversion")
        
        let processedDepthData: AVDepthData
        if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
           depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                return []
            }
        } else {
            do {
                processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
            } catch {
                return []
            }
        }
        
        let depthMap = processedDepthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let stride = bytesPerRow / MemoryLayout<Float32>.stride
        
        var points: [DepthPoint] = []
        points.reserveCapacity(width * height / 2) // Estimate
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * stride + x
                let depthValue = floatBuffer[pixelIndex]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    points.append(DepthPoint(x: Float(x), y: Float(y), depth: depthValue))
                }
            }
        }
        
        timer.lap("Converted \(points.count) valid points")
        return points
    }
    
    private func applyRefinementMask(to originalPoints: [DepthPoint]) -> [DepthPoint] {
        let timer = PerformanceTimer("Refinement Mask Application")
        
        guard let refinementMask = cameraManager.refinementMask else { return [] }
        
        let maskPixelData = extractMaskPixelData(from: refinementMask)
        let originalMaxX = Int(ceil(originalPoints.map { $0.x }.max() ?? 0))
        let originalMaxY = Int(ceil(originalPoints.map { $0.y }.max() ?? 0))
        let originalWidth = originalMaxX + 1
        let originalHeight = originalMaxY + 1
        
        // Parallel filtering
        let filteredPoints = originalPoints.filter { point in
            let x = Int(point.x)
            let y = Int(point.y)
            let displayX = originalHeight - 1 - y
            let displayY = x
            
            return isPointInMask(displayX: displayX, displayY: displayY,
                               originalWidth: originalWidth, originalHeight: originalHeight,
                               maskPixelData: maskPixelData, maskImage: refinementMask)
        }
        
        timer.lap("Filtered to \(filteredPoints.count) points")
        return filteredPoints
    }
    
    private func extractMaskPixelData(from maskImage: UIImage) -> [UInt8] {
        guard let cgImage = maskImage.cgImage else { return [] }
        
        let width = cgImage.width
        let height = cgImage.height
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelData
    }
    
    private func isPointInMask(displayX: Int, displayY: Int, originalWidth: Int, originalHeight: Int,
                              maskPixelData: [UInt8], maskImage: UIImage) -> Bool {
        guard let cgImage = maskImage.cgImage else { return false }
        
        let maskWidth = cgImage.width
        let maskHeight = cgImage.height
        
        let maskX = Int((Float(displayX) / Float(originalHeight)) * Float(maskWidth))
        let maskY = Int((Float(displayY) / Float(originalWidth)) * Float(maskHeight))
        
        guard maskX >= 0 && maskX < maskWidth && maskY >= 0 && maskY < maskHeight else { return false }
        
        let pixelIndex = (maskY * maskWidth + maskX) * 4
        guard pixelIndex < maskPixelData.count else { return false }
        
        return maskPixelData[pixelIndex] > 128
    }
    
    private func parseCSVContent(_ content: String) -> [DepthPoint] {
        let timer = PerformanceTimer("CSV Parsing")
        
        let lines = content.components(separatedBy: .newlines)
        var points: [DepthPoint] = []
        points.reserveCapacity(lines.count) // Pre-allocate
        
        // Parse camera intrinsics from comments
        for line in lines {
            if line.hasPrefix("# Camera Intrinsics:") {
                cameraIntrinsics = parseCameraIntrinsics(from: lines)
                break
            }
        }
        
        // Parallel CSV parsing
        let validLines = lines.filter { line in
            !line.hasPrefix("#") && !line.contains("x,y,depth") && !line.trimmingCharacters(in: .whitespaces).isEmpty
        }
        
        for line in validLines {
            let components = line.split(separator: ",")
            if components.count >= 3,
               let x = Float(components[0]),
               let y = Float(components[1]),
               let depth = Float(components[2]),
               !depth.isNaN && !depth.isInfinite && depth > 0 {
                points.append(DepthPoint(x: x, y: y, depth: depth))
            }
        }
        
        timer.lap("Parsed \(points.count) points")
        return points
    }
    
    private func parseCameraIntrinsics(from lines: [String]) -> CameraIntrinsics? {
        var fx: Float?, fy: Float?, cx: Float?, cy: Float?, width: Float?, height: Float?
        
        for line in lines {
            if line.hasPrefix("# Camera Intrinsics:") {
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
    
    private func create3DScene(originalDepthPoints: [DepthPoint], filteredDepthPoints: [DepthPoint]) -> SCNScene {
        let timer = PerformanceTimer("3D Scene Creation")
        
        let scene = SCNScene()
        
        // Convert to 3D
        var primaryMeasurementPoints3D = convertDepthPointsTo3D(filteredDepthPoints)
        timer.lap("Converted primary points to 3D")
        
        // Check for refinement
        var refinementMeasurementPoints3D: [SCNVector3]? = nil
        if cameraManager.refinementMask != nil {
            let refinementFilteredPoints = applyRefinementMask(to: originalDepthPoints)
            if !refinementFilteredPoints.isEmpty {
                refinementMeasurementPoints3D = convertDepthPointsTo3D(refinementFilteredPoints)
                timer.lap("Converted refinement points to 3D")
            }
        }
        
        // Convert boundary points to 3D for plane fitting
        var boundaryPoints3D: [SCNVector3]? = nil
        if !cameraManager.boundaryDepthPoints.isEmpty {
            boundaryPoints3D = convertDepthPointsTo3D(cameraManager.boundaryDepthPoints)
            print("\n🎯 CONVERTED \(boundaryPoints3D!.count) BOUNDARY POINTS TO 3D")
            timer.lap("Converted boundary points to 3D")
        }
        
        // Calculate combined center
        var allPoints = primaryMeasurementPoints3D
        if let refPoints = refinementMeasurementPoints3D {
            allPoints.append(contentsOf: refPoints)
        }
        
        let combinedBbox = calculateBoundingBox(allPoints)
        let center = SCNVector3(
            (combinedBbox.min.x + combinedBbox.max.x) / 2.0,
            (combinedBbox.min.y + combinedBbox.max.y) / 2.0,
            (combinedBbox.min.z + combinedBbox.max.z) / 2.0
        )
        
        // Shift points (vectorized operation)
        for i in 0..<primaryMeasurementPoints3D.count {
            primaryMeasurementPoints3D[i].x -= center.x
            primaryMeasurementPoints3D[i].y -= center.y
            primaryMeasurementPoints3D[i].z -= center.z
        }
        timer.lap("Centered primary points")
        
        if var refPoints = refinementMeasurementPoints3D {
            for i in 0..<refPoints.count {
                refPoints[i].x -= center.x
                refPoints[i].y -= center.y
                refPoints[i].z -= center.z
            }
            refinementMeasurementPoints3D = refPoints
            timer.lap("Centered refinement points")
        }
        
        // Center background surface points if they exist
                var centeredBackgroundPoints: [SCNVector3]? = nil
                if !cameraManager.backgroundSurfacePoints.isEmpty {
                    var bgPoints = convertDepthPointsTo3D(cameraManager.backgroundSurfacePoints)
                    for i in 0..<bgPoints.count {
                        bgPoints[i].x -= center.x
                        bgPoints[i].y -= center.y
                        bgPoints[i].z -= center.z
                    }
                    centeredBackgroundPoints = bgPoints
                    timer.lap("Centered background surface points")
                }
        
        // Create geometries (OPTIMIZED)
        let primaryPointCloudGeometry = createPointCloudGeometry(from: primaryMeasurementPoints3D)
        timer.lap("Created primary point cloud geometry")
        
        let primaryPointCloudNodeInstance = SCNNode(geometry: primaryPointCloudGeometry)
        
        let (primaryVoxelGeometry, primaryVolumeInfo) = createVoxelGeometry(from: primaryMeasurementPoints3D, refinementMask: refinementMeasurementPoints3D, backgroundPoints: centeredBackgroundPoints)
        timer.lap("Created voxel geometry")
        
        let primaryVoxelNodeInstance = SCNNode(geometry: primaryVoxelGeometry)
        
        // Create bounding box
        let bboxGeometry = createBoundingBoxGeometry(min: SCNVector3(combinedBbox.min.x - center.x, combinedBbox.min.y - center.y, combinedBbox.min.z - center.z),
                                                      max: SCNVector3(combinedBbox.max.x - center.x, combinedBbox.max.y - center.y, combinedBbox.max.z - center.z))
        let boundingBoxNodeInstance = SCNNode(geometry: bboxGeometry)
        
        // Update UI
        DispatchQueue.main.async {
            self.totalVolume = primaryVolumeInfo.totalVolume
            self.voxelCount = primaryVolumeInfo.voxelCount
            self.voxelSize = primaryVolumeInfo.voxelSize
            self.voxelNode = primaryVoxelNodeInstance
            self.primaryPointCloudNode = primaryPointCloudNodeInstance
            self.boundingBoxNode = boundingBoxNodeInstance
        }
        
        if showPrimaryPointCloud {
            scene.rootNode.addChildNode(primaryPointCloudNodeInstance)
        }
        if showVoxels {
            scene.rootNode.addChildNode(primaryVoxelNodeInstance)
        }
        if showBoundingBox {
            scene.rootNode.addChildNode(boundingBoxNodeInstance)
        }
        
        // Refinement if exists
        if let refPoints = refinementMeasurementPoints3D {
            let refinementPointCloudGeometry = createPointCloudGeometry(from: refPoints)
            let refinementPointCloudNodeInstance = SCNNode(geometry: refinementPointCloudGeometry)
            let (_, refinementVolumeInfo) = createVoxelGeometry(from: refPoints, backgroundPoints: nil, createPlaneVisualization: false)
            
            DispatchQueue.main.async {
                self.refinementVolume = refinementVolumeInfo.totalVolume
                self.refinementVoxelCount = refinementVolumeInfo.voxelCount
                self.refinementPointCloudNode = refinementPointCloudNodeInstance
            }
            
            if showRefinementPointCloud {
                scene.rootNode.addChildNode(refinementPointCloudNodeInstance)
            }
            timer.lap("Created refinement geometry")
        }
        
        setupLighting(scene: scene)
        setupCamera(scene: scene, pointCloud: primaryMeasurementPoints3D)
        timer.lap("Setup lighting and camera")
        
        return scene
    }
    
    private func convertDepthPointsTo3D(_ points: [DepthPoint]) -> [SCNVector3] {
        let timer = PerformanceTimer("3D Conversion")
        
        guard !points.isEmpty, let intrinsics = cameraIntrinsics else {
            return []
        }
        
        // Scale intrinsics
        let resolutionScaleX: Float = 640.0 / 4032.0
        let resolutionScaleY: Float = 360.0 / 2268.0
        let correctedFx = intrinsics.fx * resolutionScaleX
        let correctedFy = intrinsics.fy * resolutionScaleY
        let correctedCx = intrinsics.cx * resolutionScaleX
        let correctedCy = intrinsics.cy * resolutionScaleY
        
        // Calculate average depth ONCE
        let averageDepth = points.reduce(0.0) { $0 + $1.depth } / Float(points.count)
        
        // Vectorized conversion (process in batches if needed)
        var measurementPoints3D = [SCNVector3]()
        measurementPoints3D.reserveCapacity(points.count)
        
        for point in points {
            let realWorldX = (point.x - correctedCx) * averageDepth / correctedFx
            let realWorldY = (point.y - correctedCy) * averageDepth / correctedFy
            let realWorldZ = point.depth
            measurementPoints3D.append(SCNVector3(realWorldX, realWorldY, realWorldZ))
        }
        
        timer.lap("Converted \(points.count) points")
        return measurementPoints3D
    }
    
    private func calculateBoundingBox(_ points: [SCNVector3]) -> (min: SCNVector3, max: SCNVector3) {
        guard !points.isEmpty else { return (SCNVector3(0, 0, 0), SCNVector3(0, 0, 0)) }
        
        var minX = points[0].x, maxX = points[0].x
        var minY = points[0].y, maxY = points[0].y
        var minZ = points[0].z, maxZ = points[0].z
        
        for point in points {
            if point.x < minX { minX = point.x }
            if point.x > maxX { maxX = point.x }
            if point.y < minY { minY = point.y }
            if point.y > maxY { maxY = point.y }
            if point.z < minZ { minZ = point.z }
            if point.z > maxZ { maxZ = point.z }
        }
        
        return (SCNVector3(minX, minY, minZ), SCNVector3(maxX, maxY, maxZ))
    }
    
    // MARK: - Plane of Best Fit Functions
    
    /// Fit a plane z = ax + by + c to a set of 3D points using least squares
    private func fitPlaneToPoints(_ points: [(x: Int, y: Int, z: Int)]) -> (a: Float, b: Float, c: Float)? {
        guard points.count >= 3 else {
            print("⚠️ Need at least 3 points to fit a plane")
            return nil
        }
        
        print("✈️ Fitting plane to \(points.count) perimeter points")
        
        // Convert to Float for calculations
        let floatPoints = points.map { (x: Float($0.x), y: Float($0.y), z: Float($0.z)) }
        
        // Calculate means
        let meanX = floatPoints.reduce(0.0) { $0 + $1.x } / Float(floatPoints.count)
        let meanY = floatPoints.reduce(0.0) { $0 + $1.y } / Float(floatPoints.count)
        let meanZ = floatPoints.reduce(0.0) { $0 + $1.z } / Float(floatPoints.count)
        
        print("  Mean X: \(meanX), Y: \(meanY), Z: \(meanZ)")
        
        // Build the system of equations for least squares
        var sumXX: Float = 0, sumXY: Float = 0, sumXZ: Float = 0
        var sumYY: Float = 0, sumYZ: Float = 0
        
        for point in floatPoints {
            let dx = point.x - meanX
            let dy = point.y - meanY
            let dz = point.z - meanZ
            
            sumXX += dx * dx
            sumXY += dx * dy
            sumXZ += dx * dz
            sumYY += dy * dy
            sumYZ += dy * dz
        }
        
        // Solve the 2x2 system: [sumXX sumXY] [a] = [sumXZ]
        //                        [sumXY sumYY] [b]   [sumYZ]
        
        let determinant = sumXX * sumYY - sumXY * sumXY
        guard abs(determinant) > 1e-6 else {
            print("⚠️ Determinant too small, points may be collinear")
            return nil
        }
        
        let a = (sumXZ * sumYY - sumYZ * sumXY) / determinant
        let b = (sumYZ * sumXX - sumXZ * sumXY) / determinant
        let c = meanZ - a * meanX - b * meanY
        
        print("  Plane equation: z = \(a) * x + \(b) * y + \(c)")
        
        return (a, b, c)
    }
    
    /// Calculate Z value on the plane for given (x, y)
    private func planeZ(x: Int, y: Int, plane: (a: Float, b: Float, c: Float)) -> Int {
        let z = plane.a * Float(x) + plane.b * Float(y) + plane.c
        return Int(round(z))
    }
    
    // MARK: - Voxel Cropping Logic
    private func cropVoxelsAbovePlane() {
        guard let originalVoxels = originalFinalVoxels,
              let plane = planeCoefficients,
              let min = minBoundingBox,
              let max = maxBoundingBox,
              let node = voxelNode else {
            print("⚠️ Crop prerequisites not met. Missing original voxels, plane coefficients, or scene node.")
            return
        }

        print("✂️ Re-applying crop to plane...")
        
        // Filter the original set of voxels.
        // A voxel is kept if its Z index is less than or equal to the plane's Z index
        // at the same (X, Y) location.
        let croppedVoxels = originalVoxels.filter { voxel in
            let planeZValue = planeZ(x: voxel.x, y: voxel.y, plane: plane)
            return voxel.z < planeZValue
        }

        print("  Kept \(croppedVoxels.count) voxels out of \(originalVoxels.count)")
        
        // Re-create the 3D geometry using only the cropped voxels
        let newGeometry = createVoxelGeometryOptimized(voxels: croppedVoxels, voxelSize: voxelSize, min: min, max: max)
        SCNTransaction.begin()
        node.geometry = newGeometry
        SCNTransaction.commit()

        // Update the UI with new volume and count
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize)
        self.totalVolume = Double(croppedVoxels.count) * singleVoxelVolume
        self.voxelCount = croppedVoxels.count
        
        self.isCropped = true
    }

    private func resetCrop() {
        guard let originalVoxels = originalFinalVoxels,
              let min = minBoundingBox,
              let max = maxBoundingBox,
              let node = voxelNode else {
            print("⚠️ Reset prerequisites not met.")
            return
        }

        print("🔄 Showing full (uncropped) voxels...")
        
        // Re-create the geometry using the original, full set of voxels
        let originalGeometry = createVoxelGeometryOptimized(voxels: originalVoxels, voxelSize: voxelSize, min: min, max: max)
        SCNTransaction.begin()
        node.geometry = originalGeometry
        SCNTransaction.commit()

        // Restore the original UI stats
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize)
        self.totalVolume = Double(originalVoxels.count) * singleVoxelVolume
        self.voxelCount = originalVoxels.count
        
        self.isCropped = false
    }
    
    // MARK: - DISTANCE-BASED VOXELIZATION WITH RAY-CAST INTERIOR FILL
    private func createVoxelGeometry(from measurementPoints3D: [SCNVector3], refinementMask: [SCNVector3]? = nil, backgroundPoints: [SCNVector3]? = nil, createPlaneVisualization: Bool = true) -> (SCNGeometry, VoxelVolumeInfo) {
        let overallTimer = PerformanceTimer("VOXELIZATION")
        
        guard !measurementPoints3D.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        // STEP 1: Calculate voxel size
        let bbox = calculateBoundingBox(measurementPoints3D)
        let min = bbox.min
        let max = bbox.max
        
        let boundingBoxVolume = (max.x - min.x) * (max.y - min.y) * (max.z - min.z)
        let pointDensity = Float(measurementPoints3D.count) / boundingBoxVolume
        
        let voxelSize = pow(0.1 / pointDensity, 1.0/3.0)
        
        let gridX = Int(ceil((max.x - min.x) / voxelSize))
        let gridY = Int(ceil((max.y - min.y) / voxelSize))
        let gridZ = Int(ceil((max.z - min.z) / voxelSize))
        
        print("📊 Grid: \(gridX)×\(gridY)×\(gridZ)")
        print("📏 Voxel size: \(String(format: "%.2f", voxelSize*1000))mm")
        
        overallTimer.lap("Grid calculated")
        
        // CONVERT BOUNDARY POINTS TO VOXEL COORDINATES AND PRINT
        if !cameraManager.boundaryDepthPoints.isEmpty {
            // Get the boundary points in 3D (already centered)
            let boundaryPoints3D = convertDepthPointsTo3D(cameraManager.boundaryDepthPoints)
            
            // Center them like the main point cloud
            let combinedBbox = calculateBoundingBox(measurementPoints3D)
            let center = SCNVector3(
                (combinedBbox.min.x + combinedBbox.max.x) / 2.0,
                (combinedBbox.min.y + combinedBbox.max.y) / 2.0,
                (combinedBbox.min.z + combinedBbox.max.z) / 2.0
            )
            
            var centeredBoundaryPoints = boundaryPoints3D.map { point in
                SCNVector3(point.x - center.x, point.y - center.y, point.z - center.z)
            }
            
//            print("\n🎯 BOUNDARY POINTS IN VOXEL GRID COORDINATES:")
//            print(String(repeating: "=", count: 60))
//            print("Grid dimensions: \(gridX)×\(gridY)×\(gridZ)")
//            print("Total boundary points: \(centeredBoundaryPoints.count)")
//            print("\nFirst 50 boundary points:")
            
            for (index, point) in centeredBoundaryPoints.prefix(50).enumerated() {
                let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
                let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
                let vz = Int((point.z - min.z) / voxelSize).clamped(to: 0..<gridZ)
                
//                print("  Point \(index + 1): Voxel(\(vx), \(vy), \(vz)) | World(\(String(format: "%.4f", point.x)), \(String(format: "%.4f", point.y)), \(String(format: "%.4f", point.z))) m")
            }
            
//            if centeredBoundaryPoints.count > 50 {
//                print("  ... (\(centeredBoundaryPoints.count - 50) more points)")
//            }
            
            // Statistics
            let voxelCoords = centeredBoundaryPoints.map { point -> (Int, Int, Int) in
                let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
                let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
                let vz = Int((point.z - min.z) / voxelSize).clamped(to: 0..<gridZ)
                return (vx, vy, vz)
            }
            
            let minVoxelX = voxelCoords.map { $0.0 }.min() ?? 0
            let maxVoxelX = voxelCoords.map { $0.0 }.max() ?? 0
            let minVoxelY = voxelCoords.map { $0.1 }.min() ?? 0
            let maxVoxelY = voxelCoords.map { $0.1 }.max() ?? 0
            let minVoxelZ = voxelCoords.map { $0.2 }.min() ?? 0
            let maxVoxelZ = voxelCoords.map { $0.2 }.max() ?? 0
            
            print("\n📊 BOUNDARY VOXEL COORDINATE RANGES:")
            print("  X: \(minVoxelX) to \(maxVoxelX)")
            print("  Y: \(minVoxelY) to \(maxVoxelY)")
            print("  Z: \(minVoxelZ) to \(maxVoxelZ)")
            print(String(repeating: "=", count: 60) + "\n")
        }
        
        // STEP 2: Build spatial hash
        var spatialHash = [VoxelKey: [SCNVector3]]()
        
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
            let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
            let vz = Int((point.z - min.z) / voxelSize).clamped(to: 0..<gridZ)
            let key = VoxelKey(x: vx, y: vy, z: vz)
            
            if spatialHash[key] == nil {
                spatialHash[key] = []
            }
            spatialHash[key]?.append(point)
        }
        
        overallTimer.lap("Built spatial hash: \(spatialHash.count) cells")
        
        // STEP 3: OPTIMIZED Surface voxel detection - directly from measurement points
        var surfaceVoxels = Set<VoxelKey>()

        // First pass: Mark all voxels that contain actual measurement points
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
            let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
            let vz = Int((point.z - min.z) / voxelSize).clamped(to: 0..<gridZ)
            surfaceVoxels.insert(VoxelKey(x: vx, y: vy, z: vz))
        }

        // Second pass: Dilate by 1 voxel to ensure connectivity and smooth surface
        let occupiedVoxels = surfaceVoxels
        for voxel in occupiedVoxels {
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let nx = voxel.x + dx
                        let ny = voxel.y + dy
                        let nz = voxel.z + dz
                        if nx >= 0 && nx < gridX && ny >= 0 && ny < gridY && nz >= 0 && nz < gridZ {
                            surfaceVoxels.insert(VoxelKey(x: nx, y: ny, z: nz))
                        }
                    }
                }
            }
        }

        overallTimer.lap("Filled \(surfaceVoxels.count) SURFACE voxels (OPTIMIZED)")
        
        // STEP 4: Ray-cast interior fill (respects surface boundary)
        let filledVoxels = fillInteriorRayCast(surfaceVoxels: surfaceVoxels, gridX: gridX, gridY: gridY, gridZ: gridZ)
        overallTimer.lap("Interior fill complete: \(filledVoxels.count) total voxels")
        
        // STEP 5: Apply refinement mask
        var finalVoxels = filledVoxels
        if let refinementPoints = refinementMask, !refinementPoints.isEmpty {
            var refinementXYSet = Set<XYKey>()
            
            for point in refinementPoints {
                let gridX = Int((point.x - min.x) / voxelSize)
                let gridY = Int((point.y - min.y) / voxelSize)
                refinementXYSet.insert(XYKey(x: gridX, y: gridY))
            }
            
            finalVoxels = finalVoxels.filter { voxel in
                refinementXYSet.contains(XYKey(x: voxel.x, y: voxel.y))
            }
            overallTimer.lap("Applied refinement: \(finalVoxels.count) voxels remain")
        }
        
        guard !finalVoxels.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        // STEP 6: Calculate plane of best fit for floor (ALWAYS based on background surface points)
                print("\n🎯 PLANE FLOOR CALCULATION")

                // Use background surface points if available, otherwise fall back to convex hull method
                var planePoints3D: [(x: Int, y: Int, z: Int)] = []
                var hullPointsForVisualization: [(x: Int, y: Int)] = []

        if let bgPoints = backgroundPoints, !bgPoints.isEmpty {
                    print("  Using \(bgPoints.count) user-selected background surface points for plane fitting")
                    
                    // Convert background points (already centered) to voxel grid coordinates
                    for point in bgPoints {
                        let vx = Int((point.x - min.x) / voxelSize)
                        let vy = Int((point.y - min.y) / voxelSize)
                        let vz = Int((point.z - min.z) / voxelSize)
                        
                        planePoints3D.append((x: vx, y: vy, z: vz))
                        hullPointsForVisualization.append((x: vx, y: vy))
                    }
                    
                    print("  Converted background surface points to voxel coordinates: \(planePoints3D.count)")
                } else {
                    print("  No background surface points available, falling back to convex hull method")
                    
                    // Original method: Build max Z map for each XY coordinate using PRIMARY voxels
                    var maxZMap: [XYKey: Int] = [:]
                    for voxel in filledVoxels {
                        let key = XYKey(x: voxel.x, y: voxel.y)
                        if let existingZ = maxZMap[key] {
                            maxZMap[key] = Swift.max(existingZ, voxel.z)
                        } else {
                            maxZMap[key] = voxel.z
                        }
                    }
                    
                    print("  Found \(maxZMap.count) unique XY columns")
                    
                    // Get unique XY coordinates for hull calculation
                    var xyPoints: [(x: Int, y: Int)] = []
                    for (key, _) in maxZMap {
                        xyPoints.append((x: key.x, y: key.y))
                    }
                    
                    // Find convex hull to get perimeter
                    let hull = fastConvexHull2D(xyPoints)
                    print("  Convex hull has \(hull.count) perimeter points")
                    
                    // Get 3D coordinates of hull perimeter points
                    for point in hull {
                        let key = XYKey(x: point.x, y: point.y)
                        if let z = maxZMap[key] {
                            planePoints3D.append((x: point.x, y: point.y, z: z))
                            hullPointsForVisualization.append((x: point.x, y: point.y))
                        }
                    }
                    
                    print("  Hull perimeter 3D points: \(planePoints3D.count)")
                }

        // Fit plane to the selected points (boundary or hull)
        guard let plane = fitPlaneToPoints(planePoints3D) else {
            print("⚠️ Failed to fit plane to points")
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }

        // Build maxZMap for all primary voxels (needed for floor map and logging)
        var maxZMap: [XYKey: Int] = [:]
        for voxel in filledVoxels {
            let key = XYKey(x: voxel.x, y: voxel.y)
            if let existingZ = maxZMap[key] {
                maxZMap[key] = Swift.max(existingZ, voxel.z)
            } else {
                maxZMap[key] = voxel.z
            }
        }

        // Build minZMap from PRIMARY MEASUREMENT POINTS using CONTINUOUS Z values
        var minZMap: [XYKey: Float] = [:]  // Changed to Float for precision
        print("\n🎯 BUILDING MIN Z MAP FROM PRIMARY MEASUREMENT POINTS (CONTINUOUS)")
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
            let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
            
            // Store CONTINUOUS Z in grid coordinates (not truncated)
            let continuousVZ = (point.z - min.z) / voxelSize
            let key = XYKey(x: vx, y: vy)
            
            if let existingZ = minZMap[key] {
                minZMap[key] = Swift.min(existingZ, continuousVZ)
            } else {
                minZMap[key] = continuousVZ
            }
        }
        print("  Built minZMap with \(minZMap.count) XY columns from primary points")

        // Store plane coefficients and create floor map using plane equation
        var planeFloorMapLocal: [XYKey: Int] = [:]

        print("\n📋 PLANE Z VALUES FOR EACH XY COLUMN:")
        for (key, _) in maxZMap {
            let planeZValue = planeZ(x: key.x, y: key.y, plane: plane)
            planeFloorMapLocal[key] = planeZValue
        }
        print("  Calculated plane Z values for \(maxZMap.count) XY columns")

        // Update state variables for cropping (only if creating plane visualization)
        if createPlaneVisualization {
            // COMBINED: Crop voxels above plane AND outside point cloud in ONE pass
            let finalCroppedVoxels = finalVoxels.filter { voxel in
                let planeZValue = planeZ(x: voxel.x, y: voxel.y, plane: plane)
                guard voxel.z < planeZValue else { return false }
                
                let key = XYKey(x: voxel.x, y: voxel.y)
                guard let minZContinuous = minZMap[key] else { return false }
                
                return Float(voxel.z) >= minZContinuous
            }
                            
            DispatchQueue.main.async {
                    self.planeCoefficients = plane
                    self.planeFloorMap = planeFloorMapLocal
                    self.originalFinalVoxels = finalVoxels
                    self.minBoundingBox = min
                    self.maxBoundingBox = max
                    self.isCropped = true  // Mark as already cropped
                }
                
                // Use cropped voxels for display
                finalVoxels = finalCroppedVoxels
            }

        // Create plane visualization (only if requested, not for refinement-only calculations)
        if createPlaneVisualization {
            if let planeGeometry = createPlaneVisualizationGeometry(hull: hullPointsForVisualization, plane: plane, voxelSize: voxelSize, min: min) {
                let planeNode = SCNNode(geometry: planeGeometry)
                DispatchQueue.main.async {
                    self.planeVisualizationNode = planeNode
                    if self.showPlaneVisualization {
                        self.scene?.rootNode.addChildNode(planeNode)
                    }
                }
            }
        }

        overallTimer.lap("Plane floor calculation complete")
        
        // STEP 7: Calculate volume
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize)
        let totalVolumeM3 = Double(finalVoxels.count) * singleVoxelVolume
        let volumeInfo = VoxelVolumeInfo(totalVolume: totalVolumeM3, voxelCount: finalVoxels.count, voxelSize: voxelSize)
        
        // STEP 8: Create geometry
        let geometry = createVoxelGeometryOptimized(voxels: finalVoxels, voxelSize: voxelSize, min: min, max: max)
        overallTimer.lap("Created SCNGeometry")
        
        return (geometry, volumeInfo)
    }

    // MARK: - Ray-Cast Interior Fill (Preserves Surface Detail)
    private func fillInteriorRayCast(surfaceVoxels: Set<VoxelKey>, gridX: Int, gridY: Int, gridZ: Int) -> Set<VoxelKey> {
        let timer = PerformanceTimer("Ray-Cast Interior Fill")
        
        // Find bounding box of surface voxels
        let minX = surfaceVoxels.map { $0.x }.min() ?? 0
        let maxX = surfaceVoxels.map { $0.x }.max() ?? 0
        let minY = surfaceVoxels.map { $0.y }.min() ?? 0
        let maxY = surfaceVoxels.map { $0.y }.max() ?? 0
        let minZ = surfaceVoxels.map { $0.z }.min() ?? 0
        let maxZ = surfaceVoxels.map { $0.z }.max() ?? 0
        
        print("Surface bbox: X[\(minX)-\(maxX)] Y[\(minY)-\(maxY)] Z[\(minZ)-\(maxZ)]")
        
        // Build fast lookup set
        let surfaceSet = surfaceVoxels
        
        var allVoxels = surfaceVoxels
        var interiorCount = 0
        let lock = NSLock()
        
        // Generate candidate interior positions (only within surface bounds)
        var candidates: [VoxelKey] = []
        for x in (minX + 1)..<maxX {
            for y in (minY + 1)..<maxY {
                for z in (minZ + 1)..<maxZ {
                    let key = VoxelKey(x: x, y: y, z: z)
                    if !surfaceSet.contains(key) {
                        candidates.append(key)
                    }
                }
            }
        }
        
        timer.lap("Generated \(candidates.count) candidate positions")
        
        // Parallel ray-cast check
        DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
            let candidate = candidates[index]
            
            // Cast ray in -Z direction only (downward)
            var allRaysHitSurface = true
            
            // Ray -Z
            var hitSurface = false
            for testZ in stride(from: candidate.z - 1, through: minZ, by: -1) {
                if surfaceSet.contains(VoxelKey(x: candidate.x, y: candidate.y, z: testZ)) {
                    hitSurface = true
                    break
                }
            }
            if !hitSurface { allRaysHitSurface = false }
            
            // If ray hit surface, this voxel is interior
            if allRaysHitSurface {
                lock.lock()
                allVoxels.insert(candidate)
                interiorCount += 1
                lock.unlock()
            }
        }
        
        timer.lap("Ray-cast complete")
        print("Surface: \(surfaceVoxels.count), Interior: \(interiorCount), Total: \(allVoxels.count)")
        
        return allVoxels
    }
    
    // OPTIMIZED: Fast convex hull using Andrew's monotone chain (O(n log n))
    private func fastConvexHull2D(_ points: [(x: Int, y: Int)]) -> [(x: Int, y: Int)] {
        if points.count < 3 { return points }
        
        // Remove duplicates and sort
        let uniquePoints = Array(Set(points.map { "\($0.x),\($0.y)" }))
            .compactMap { key -> (x: Int, y: Int)? in
                let parts = key.split(separator: ",")
                guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { return nil }
                return (x: x, y: y)
            }
            .sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        
        if uniquePoints.count < 3 { return uniquePoints }
        
        // Build lower hull
        var lower: [(x: Int, y: Int)] = []
        for p in uniquePoints {
            while lower.count >= 2 {
                let cross = (lower[lower.count-1].x - lower[lower.count-2].x) * (p.y - lower[lower.count-2].y) -
                           (lower[lower.count-1].y - lower[lower.count-2].y) * (p.x - lower[lower.count-2].x)
                if cross > 0 { break }
                lower.removeLast()
            }
            lower.append(p)
        }
        
        // Build upper hull
        var upper: [(x: Int, y: Int)] = []
        for p in uniquePoints.reversed() {
            while upper.count >= 2 {
                let cross = (upper[upper.count-1].x - upper[upper.count-2].x) * (p.y - upper[upper.count-2].y) -
                           (upper[upper.count-1].y - upper[upper.count-2].y) * (p.x - upper[upper.count-2].x)
                if cross > 0 { break }
                upper.removeLast()
            }
            upper.append(p)
        }
        
        // Remove last point of each half because it's repeated
        lower.removeLast()
        upper.removeLast()
        
        return lower + upper
    }

    // Create plane visualization geometry
    private func createPlaneVisualizationGeometry(hull: [(x: Int, y: Int)], plane: (a: Float, b: Float, c: Float), voxelSize: Float, min: SCNVector3) -> SCNGeometry? {
        guard hull.count >= 3 else { return nil }
        
        print("🎨 Creating extended plane visualization")
        
        // Find bounds of hull points
        let minHullX = hull.map { $0.x }.min() ?? 0
        let maxHullX = hull.map { $0.x }.max() ?? 0
        let minHullY = hull.map { $0.y }.min() ?? 0
        let maxHullY = hull.map { $0.y }.max() ?? 0
        
        // Extend the bounds significantly (5x in each direction for "infinite" appearance)
        let extensionFactor: Float = 20.0
        let rangeX = Float(maxHullX - minHullX)
        let rangeY = Float(maxHullY - minHullY)
        let extendedMinX = Int(Float(minHullX) - rangeX * extensionFactor)
        let extendedMaxX = Int(Float(maxHullX) + rangeX * extensionFactor)
        let extendedMinY = Int(Float(minHullY) - rangeY * extensionFactor)
        let extendedMaxY = Int(Float(maxHullY) + rangeY * extensionFactor)
        
        // Create 4 corners of extended rectangular plane
        let corners = [
            (x: extendedMinX, y: extendedMinY),
            (x: extendedMaxX, y: extendedMinY),
            (x: extendedMaxX, y: extendedMaxY),
            (x: extendedMinX, y: extendedMaxY)
        ]
        
        // Convert corners to 3D vertices using plane equation for Z values (UNCHANGED)
        var vertices: [SCNVector3] = []
        for point in corners {
            let x = min.x + (Float(point.x) + 0.5) * voxelSize
            let y = min.y + (Float(point.y) + 0.5) * voxelSize
            
            // Calculate Z using plane equation (SAME AS BEFORE)
            let z = plane.a * Float(point.x) + plane.b * Float(point.y) + plane.c
            let z3D = min.z + (z + 0.5) * voxelSize
            
            vertices.append(SCNVector3(x, y, z3D))
            print("  Extended plane vertex: (\(point.x), \(point.y)) -> Plane Z=\(Int(round(z))) -> 3D: (\(x), \(y), \(z3D))")
        }
        
        // Create two triangles to form the rectangle
        let indices: [UInt32] = [
            0, 1, 2,  // First triangle
            0, 2, 3   // Second triangle
        ]
        
        // Create geometry (UNCHANGED)
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
        
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 1.0, green: 0.4, blue: 0.8, alpha: 0.6) // Pink/Magenta
        material.lightingModel = .lambert
        material.isDoubleSided = true
        geometry.materials = [material]
        
        print("✨ Extended plane geometry created with \(vertices.count) vertices, \(indices.count/3) triangles")
        
        return geometry
    }
    
    // ULTRA-OPTIMIZED: Batch geometry creation with pre-computed indices
    private func createVoxelGeometryOptimized(voxels: Set<VoxelKey>, voxelSize: Float, min: SCNVector3, max: SCNVector3) -> SCNGeometry {
        let timer = PerformanceTimer("Geometry Creation")
        
        let voxelCount = voxels.count
        guard voxelCount > 0 else { return SCNGeometry() }
        
        let vertexCount = voxelCount * 8
        let indexCount = voxelCount * 36
        
        // Pre-allocate all memory at once
        var voxelVertices = [SCNVector3](repeating: SCNVector3(0, 0, 0), count: vertexCount)
        var voxelColors = [SCNVector3](repeating: SCNVector3(0, 0, 0), count: vertexCount)
        var indices = [UInt32](repeating: 0, count: indexCount)
        
        let halfSize = voxelSize * 0.5
        let depthRange = max.z - min.z
        
        // Pre-compute cube vertex offsets (relative to center)
        let cubeOffsets: [(Float, Float, Float)] = [
            (-halfSize, -halfSize, -halfSize),
            ( halfSize, -halfSize, -halfSize),
            ( halfSize,  halfSize, -halfSize),
            (-halfSize,  halfSize, -halfSize),
            (-halfSize, -halfSize,  halfSize),
            ( halfSize, -halfSize,  halfSize),
            ( halfSize,  halfSize,  halfSize),
            (-halfSize,  halfSize,  halfSize)
        ]
        
        // Pre-compute cube face indices (reusable pattern)
        let cubeIndices: [UInt32] = [
            0, 1, 2,  2, 3, 0,  // Front
            4, 5, 6,  6, 7, 4,  // Back
            0, 4, 7,  7, 3, 0,  // Left
            1, 5, 6,  6, 2, 1,  // Right
            3, 2, 6,  6, 7, 3,  // Top
            0, 1, 5,  5, 4, 0   // Bottom
        ]
        
        var currentVoxelIndex = 0
        
        // Process all voxels in one pass
        for voxel in voxels {
            let centerX = min.x + (Float(voxel.x) + 0.5) * voxelSize
            let centerY = min.y + (Float(voxel.y) + 0.5) * voxelSize
            let centerZ = min.z + (Float(voxel.z) + 0.5) * voxelSize
            
            let vertexBaseIndex = currentVoxelIndex * 8
            let indexBaseIndex = currentVoxelIndex * 36
            
            // Generate 8 vertices for this cube
            for i in 0..<8 {
                let offset = cubeOffsets[i]
                voxelVertices[vertexBaseIndex + i] = SCNVector3(
                    centerX + offset.0,
                    centerY + offset.1,
                    centerZ + offset.2
                )
            }
            
            // Calculate color once for all 8 vertices
            let normalizedDepth = depthRange > 0 ? (centerZ - min.z) / depthRange : 0
            let invertedDepth = 1.0 - normalizedDepth
            let color = depthToColor(invertedDepth)
            
            for i in 0..<8 {
                voxelColors[vertexBaseIndex + i] = color
            }
            
            // Generate 36 indices for this cube (12 triangles * 3 vertices)
            let baseVertex = UInt32(vertexBaseIndex)
            for i in 0..<36 {
                indices[indexBaseIndex + i] = baseVertex + cubeIndices[i]
            }
            
            currentVoxelIndex += 1
        }
        
        timer.lap("Generated \(vertexCount) vertices and \(indexCount) indices")
        
        // Create geometry sources efficiently
        let vertexData = Data(bytes: voxelVertices, count: vertexCount * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let colorData = Data(bytes: voxelColors, count: vertexCount * MemoryLayout<SCNVector3>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertexCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let indexData = Data(bytes: indices, count: indexCount * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indexCount / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.transparency = 0.7
        geometry.materials = [material]
        
        timer.lap("Created final SCNGeometry")
        return geometry
    }
    
    private func createPointCloudGeometry(from measurementPoints3D: [SCNVector3]) -> SCNGeometry {
        guard !measurementPoints3D.isEmpty else { return SCNGeometry() }
        
        let bbox = calculateBoundingBox(measurementPoints3D)
        let depthRange = bbox.max.z - bbox.min.z
        
        var colors: [SCNVector3] = []
        colors.reserveCapacity(measurementPoints3D.count)
        
        for point in measurementPoints3D {
            let normalizedDepth = depthRange > 0 ? (point.z - bbox.min.z) / depthRange : 0
            let invertedDepth = 1.0 - normalizedDepth
            colors.append(depthToColor(invertedDepth))
        }
        
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
        
        let indices: [UInt32] = Array(0..<UInt32(measurementPoints3D.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: measurementPoints3D.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
    
    private func createBoundaryPointCloudGeometry(from boundaryPoints3D: [SCNVector3]) -> SCNGeometry {
        guard !boundaryPoints3D.isEmpty else { return SCNGeometry() }
        
        // Use bright orange color for all boundary points
        let orangeColor = SCNVector3(1.0, 0.5, 0.0)  // Bright orange (RGB: 255, 128, 0)
        var colors: [SCNVector3] = []
        colors.reserveCapacity(boundaryPoints3D.count)
        
        for _ in boundaryPoints3D {
            colors.append(orangeColor)
        }
        
        let vertexData = Data(bytes: boundaryPoints3D, count: boundaryPoints3D.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: boundaryPoints3D.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
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
        
        let indices: [UInt32] = Array(0..<UInt32(boundaryPoints3D.count))
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .point,
            primitiveCount: boundaryPoints3D.count,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        geometry.materials = [material]
        
        return geometry
    }
    
    private func createBoundingBoxGeometry(min: SCNVector3, max: SCNVector3) -> SCNGeometry {
        // 8 corners of the bounding box
        let corners: [SCNVector3] = [
            SCNVector3(min.x, min.y, min.z), // 0
            SCNVector3(max.x, min.y, min.z), // 1
            SCNVector3(max.x, max.y, min.z), // 2
            SCNVector3(min.x, max.y, min.z), // 3
            SCNVector3(min.x, min.y, max.z), // 4
            SCNVector3(max.x, min.y, max.z), // 5
            SCNVector3(max.x, max.y, max.z), // 6
            SCNVector3(min.x, max.y, max.z)  // 7
        ]
        
        // 12 edges of the box (as pairs of vertex indices)
        let edges: [UInt32] = [
            0, 1,  1, 2,  2, 3,  3, 0,  // Bottom face
            4, 5,  5, 6,  6, 7,  7, 4,  // Top face
            0, 4,  1, 5,  2, 6,  3, 7   // Vertical edges
        ]
        
        let vertexData = Data(bytes: corners, count: corners.count * MemoryLayout<SCNVector3>.size)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: corners.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.size
        )
        
        let indexData = Data(bytes: edges, count: edges.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: edges.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.yellow
        material.lightingModel = .constant
        geometry.materials = [material]
        
        return geometry
    }
    
    private func depthToColor(_ normalizedDepth: Float) -> SCNVector3 {
        let t = normalizedDepth
        
        if t < 0.25 {
            let local_t = t / 0.25
            return SCNVector3(0, local_t, 1)
        } else if t < 0.5 {
            let local_t = (t - 0.25) / 0.25
            return SCNVector3(0, 1, 1 - local_t)
        } else if t < 0.75 {
            let local_t = (t - 0.5) / 0.25
            return SCNVector3(local_t, 1, 0)
        } else {
            let local_t = (t - 0.75) / 0.25
            return SCNVector3(1, 1 - local_t, 0)
        }
    }
    
    private func setupLighting(scene: SCNScene) {
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor.white
        ambientLight.intensity = 400
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = UIColor.white
        directionalLight.intensity = 600
        let lightNode = SCNNode()
        lightNode.light = directionalLight
        lightNode.position = SCNVector3(10, 15, 10)
        lightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(lightNode)
        
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

// MARK: - Helper Structs for Optimization
struct VoxelKey: Hashable {
    let x: Int
    let y: Int
    let z: Int
}

struct XYKey: Hashable {
    let x: Int
    let y: Int
}

extension Int {
    func clamped(to range: Range<Int>) -> Int {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound - 1, self))
    }
}
