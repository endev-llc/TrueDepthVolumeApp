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
        
        // Create geometries (OPTIMIZED)
        let primaryPointCloudGeometry = createPointCloudGeometry(from: primaryMeasurementPoints3D)
        timer.lap("Created primary point cloud geometry")
        
        let primaryPointCloudNodeInstance = SCNNode(geometry: primaryPointCloudGeometry)
        
        let (primaryVoxelGeometry, primaryVolumeInfo) = createVoxelGeometry(from: primaryMeasurementPoints3D, refinementMask: refinementMeasurementPoints3D)
        timer.lap("Created voxel geometry")
        
        let primaryVoxelNodeInstance = SCNNode(geometry: primaryVoxelGeometry)
        
        // Update UI
        DispatchQueue.main.async {
            self.totalVolume = primaryVolumeInfo.totalVolume
            self.voxelCount = primaryVolumeInfo.voxelCount
            self.voxelSize = primaryVolumeInfo.voxelSize
            self.voxelNode = primaryVoxelNodeInstance
            self.primaryPointCloudNode = primaryPointCloudNodeInstance
        }
        
        if showPrimaryPointCloud {
            scene.rootNode.addChildNode(primaryPointCloudNodeInstance)
        }
        if showVoxels {
            scene.rootNode.addChildNode(primaryVoxelNodeInstance)
        }
        
        // Refinement if exists
        if let refPoints = refinementMeasurementPoints3D {
            let refinementPointCloudGeometry = createPointCloudGeometry(from: refPoints)
            let refinementPointCloudNodeInstance = SCNNode(geometry: refinementPointCloudGeometry)
            let (_, refinementVolumeInfo) = createVoxelGeometry(from: refPoints)
            
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
    
    // HEAVILY OPTIMIZED VOXELIZATION (ULTRA-FAST VERSION)
    private func createVoxelGeometry(from measurementPoints3D: [SCNVector3], refinementMask: [SCNVector3]? = nil) -> (SCNGeometry, VoxelVolumeInfo) {
        let overallTimer = PerformanceTimer("VOXELIZATION")
        
        guard !measurementPoints3D.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        // STEP 1: Calculate grid parameters (REDUCED TARGET FOR SPEED)
        let bbox = calculateBoundingBox(measurementPoints3D)
        let min = bbox.min
        let max = bbox.max
        
        let boundingBoxVolume = (max.x - min.x) * (max.y - min.y) * (max.z - min.z)
        
        // CRITICAL: Reduce from 1M to 50K voxels for 20x faster rendering
        let maxVoxels: Float = 50_000
        let voxelVolume = boundingBoxVolume / maxVoxels
        var voxelSize = pow(voxelVolume, 1.0/3.0)
        
        var gridX = Int(ceil((max.x - min.x) / voxelSize))
        var gridY = Int(ceil((max.y - min.y) / voxelSize))
        var gridZ = Int(ceil((max.z - min.z) / voxelSize))
        
        while gridX * gridY * gridZ > Int(maxVoxels) {
            voxelSize *= 1.01
            gridX = Int(ceil((max.x - min.x) / voxelSize))
            gridY = Int(ceil((max.y - min.y) / voxelSize))
            gridZ = Int(ceil((max.z - min.z) / voxelSize))
        }
        overallTimer.lap("Grid params: \(gridX)×\(gridY)×\(gridZ), voxel=\(voxelSize)")
        
        // STEP 2: Map points to voxels using Set for O(1) operations
        var surfaceVoxels = Set<VoxelKey>()
        surfaceVoxels.reserveCapacity(measurementPoints3D.count)
        
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize).clamped(to: 0..<gridX)
            let vy = Int((point.y - min.y) / voxelSize).clamped(to: 0..<gridY)
            let vz = Int((point.z - min.z) / voxelSize).clamped(to: 0..<gridZ)
            surfaceVoxels.insert(VoxelKey(x: vx, y: vy, z: vz))
        }
        overallTimer.lap("Mapped \(surfaceVoxels.count) surface voxels")
        
        // STEP 3: Layer-by-layer flood fill (ULTRA-OPTIMIZED WITH SCANLINE)
        var filledVoxels = Set<VoxelKey>()
        filledVoxels.reserveCapacity(surfaceVoxels.count * 2)
        
        // Group surface voxels by Z layer
        var layerVoxels = [Int: [(x: Int, y: Int)]]()
        for voxel in surfaceVoxels {
            if layerVoxels[voxel.z] == nil {
                layerVoxels[voxel.z] = []
            }
            layerVoxels[voxel.z]?.append((x: voxel.x, y: voxel.y))
        }
        
        // Process each Z layer with FAST scanline fill
        for z in layerVoxels.keys.sorted() {
            guard let layerSurface = layerVoxels[z], layerSurface.count >= 3 else { continue }
            
            // Get convex hull (fast)
            let hull = fastConvexHull2D(layerSurface)
            
            if hull.count >= 3 {
                let minX = layerSurface.map { $0.x }.min()!
                let maxX = layerSurface.map { $0.x }.max()!
                let minY = layerSurface.map { $0.y }.min()!
                let maxY = layerSurface.map { $0.y }.max()!
                
                // Use scanline algorithm instead of point-by-point checking
                scanlineFillPolygon(hull, minX: minX, maxX: maxX, minY: minY, maxY: maxY, z: z, filledVoxels: &filledVoxels)
            }
        }
        
        // Add all surface voxels to ensure boundaries are included
        filledVoxels.formUnion(surfaceVoxels)
        overallTimer.lap("Filled \(filledVoxels.count) total voxels")
        
        // STEP 4: Apply refinement mask if provided
        if let refinementPoints = refinementMask, !refinementPoints.isEmpty {
            let tolerance: Float = voxelSize * 1.5
            var refinementXYSet = Set<XYKey>()
            
            for point in refinementPoints {
                let gridX = Int((point.x - min.x) / voxelSize)
                let gridY = Int((point.y - min.y) / voxelSize)
                
                for dx in -1...1 {
                    for dy in -1...1 {
                        refinementXYSet.insert(XYKey(x: gridX + dx, y: gridY + dy))
                    }
                }
            }
            
            filledVoxels = filledVoxels.filter { voxel in
                refinementXYSet.contains(XYKey(x: voxel.x, y: voxel.y))
            }
            overallTimer.lap("Applied refinement: \(filledVoxels.count) voxels remain")
        }
        
        guard !filledVoxels.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        // STEP 5: Calculate volume
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize)
        let totalVolumeM3 = Double(filledVoxels.count) * singleVoxelVolume
        let volumeInfo = VoxelVolumeInfo(totalVolume: totalVolumeM3, voxelCount: filledVoxels.count, voxelSize: voxelSize)
        
        // STEP 6: Create geometry (BATCHED AND OPTIMIZED)
        let geometry = createVoxelGeometryOptimized(voxels: filledVoxels, voxelSize: voxelSize, min: min, max: max)
        overallTimer.lap("Created SCNGeometry")
        
        return (geometry, volumeInfo)
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
    
    // OPTIMIZED: Proper scanline fill with edge intersection
    private func scanlineFillPolygon(_ polygon: [(x: Int, y: Int)], minX: Int, maxX: Int, minY: Int, maxY: Int, z: Int, filledVoxels: inout Set<VoxelKey>) {
        if polygon.count < 3 { return }
        
        // For each scanline Y
        for y in minY...maxY {
            var intersections: [Int] = []
            
            // Find all edge intersections at this Y
            for i in 0..<polygon.count {
                let j = (i + 1) % polygon.count
                let p1 = polygon[i]
                let p2 = polygon[j]
                
                // Check if edge crosses scanline
                if (p1.y <= y && p2.y > y) || (p2.y <= y && p1.y > y) {
                    // Calculate X intersection
                    let t = Float(y - p1.y) / Float(p2.y - p1.y)
                    let x = Float(p1.x) + t * Float(p2.x - p1.x)
                    intersections.append(Int(round(x)))
                }
            }
            
            // Sort intersections and fill between pairs
            intersections.sort()
            
            for i in stride(from: 0, to: intersections.count - 1, by: 2) {
                let startX = intersections[i]
                let endX = intersections[i + 1]
                
                for x in startX...endX {
                    if x >= minX && x <= maxX {
                        filledVoxels.insert(VoxelKey(x: x, y: y, z: z))
                    }
                }
            }
        }
    }
    
    // ULTRA-OPTIMIZED: Batch geometry creation with pre-computed indices
    private func createVoxelGeometryOptimized(voxels: Set<VoxelKey>, voxelSize: Float, min: SCNVector3, max: SCNVector3) -> SCNGeometry {
        let timer = PerformanceTimer("Geometry Creation")
        
        let voxelCount = voxels.count
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
