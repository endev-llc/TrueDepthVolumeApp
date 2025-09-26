//
//  DepthVisualization3DView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//

import SwiftUI
import SceneKit
import AVFoundation

// MARK: - 3D Depth Visualization View with Voxels
struct DepthVisualization3DView: View {
    let csvFileURL: URL
    let cameraManager: CameraManager // Added CameraManager parameter
    let onDismiss: () -> Void
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    @State private var totalVolume: Double = 0.0
    @State private var voxelCount: Int = 0
    @State private var voxelSize: Float = 0.0
    @State private var refinementVolume: Double = 0.0 // Added refinement volume
    @State private var refinementVoxelCount: Int = 0 // Added refinement voxel count
    @State private var cameraIntrinsics: CameraIntrinsics? = nil
    @State private var showVoxels: Bool = true
    @State private var showRefinementVoxels: Bool = true // Added refinement toggle
    @State private var voxelNode: SCNNode?
    @State private var refinementVoxelNode: SCNNode? // Added refinement voxel node
    
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
                                
                                if refinementVoxelCount > 0 {
                                    Text("Refined: \(String(format: "%.2f", refinementVolume * 1_000_000)) cm³")
                                        .foregroundColor(.green)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                
                                Text("\(voxelCount) voxels • \(String(format: "%.1f", voxelSize * 1000))mm each")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Voxel toggles
                    VStack(spacing: 8) {
                        Toggle("Primary", isOn: $showVoxels)
                            .foregroundColor(.cyan)
                            .font(.caption)
                            .toggleStyle(SwitchToggleStyle(tint: .cyan))
                            .onChange(of: showVoxels) { _, newValue in
                                toggleVoxelVisibility(show: newValue)
                            }
                        
                        if refinementVoxelNode != nil {
                            Toggle("Refined", isOn: $showRefinementVoxels)
                                .foregroundColor(.green)
                                .font(.caption)
                                .toggleStyle(SwitchToggleStyle(tint: .green))
                                .onChange(of: showRefinementVoxels) { _, newValue in
                                    toggleRefinementVoxelVisibility(show: newValue)
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
    
    private func toggleRefinementVoxelVisibility(show: Bool) {
        guard let refinementVoxelNode = refinementVoxelNode else { return }
        
        if show {
            scene?.rootNode.addChildNode(refinementVoxelNode)
        } else {
            refinementVoxelNode.removeFromParentNode()
        }
    }
    
    private func loadAndCreate3DScene() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load original unfiltered depth data
                let originalDepthPoints = getOriginalDepthData()
                
                // Parse CSV to get the filtered points (from original mask)
                let csvContent = try String(contentsOf: csvFileURL)
                let filteredDepthPoints = parseCSVContent(csvContent)
                
                let scene = create3DScene(originalDepthPoints: originalDepthPoints, filteredDepthPoints: filteredDepthPoints)
                
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
        // Get original unfiltered data from CameraManager
        if !cameraManager.uploadedCSVData.isEmpty {
            return cameraManager.uploadedCSVData
        } else if let rawDepthData = cameraManager.rawDepthData {
            return convertDepthDataToPoints(rawDepthData)
        }
        return []
    }
    
    private func convertDepthDataToPoints(_ depthData: AVDepthData) -> [DepthPoint] {
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
        
        var points: [DepthPoint] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    points.append(DepthPoint(x: Float(x), y: Float(y), depth: depthValue))
                }
            }
        }
        
        return points
    }
    
    private func applyRefinementMask(to originalPoints: [DepthPoint]) -> [DepthPoint] {
        guard let refinementMask = cameraManager.refinementMask else { return [] }
        
        let imageFrame = cameraManager.refinementImageFrame
        let depthImageSize = cameraManager.refinementDepthImageSize
        
        var filteredPoints: [DepthPoint] = []
        let maskPixelData = extractMaskPixelData(from: refinementMask)
        
        // Get original data dimensions (same logic as CameraManager)
        let originalMaxX = Int(ceil(originalPoints.map { $0.x }.max() ?? 0))
        let originalMaxY = Int(ceil(originalPoints.map { $0.y }.max() ?? 0))
        let originalWidth = originalMaxX + 1
        let originalHeight = originalMaxY + 1
        
        for point in originalPoints {
            let x = Int(point.x)
            let y = Int(point.y)
            
            // Transform to display coordinates (same rotation as CameraManager)
            let displayX = originalHeight - 1 - y
            let displayY = x
            
            // Check if this point falls within the refinement mask
            if isPointInMask(displayX: displayX, displayY: displayY,
                           originalWidth: originalWidth, originalHeight: originalHeight,
                           maskPixelData: maskPixelData, maskImage: refinementMask) {
                filteredPoints.append(point)
            }
        }
        
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
        
        // Convert display coordinates to mask image coordinates
        let maskX = Int((Float(displayX) / Float(originalHeight)) * Float(maskWidth))
        let maskY = Int((Float(displayY) / Float(originalWidth)) * Float(maskHeight))
        
        // Check bounds
        guard maskX >= 0 && maskX < maskWidth && maskY >= 0 && maskY < maskHeight else { return false }
        
        // Check if the mask pixel at this location is above threshold
        let pixelIndex = (maskY * maskWidth + maskX) * 4
        guard pixelIndex < maskPixelData.count else { return false }
        
        let red = maskPixelData[pixelIndex]
        return red > 128 // Threshold for mask inclusion
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
            
            if components.count >= 3 {
                guard let x = Float(components[0]),
                      let y = Float(components[1]),
                      let depth = Float(components[2]) else { continue }
                
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
        let scene = SCNScene()
        
        // Convert filtered depth points to 3D coordinates (primary structure)
        var primaryMeasurementPoints3D = convertDepthPointsTo3D(filteredDepthPoints)
        
        // Check if refinement mask exists and create secondary structure
        var refinementMeasurementPoints3D: [SCNVector3]? = nil
        if cameraManager.refinementMask != nil {
            let refinementFilteredPoints = applyRefinementMask(to: originalDepthPoints)
            
            if !refinementFilteredPoints.isEmpty {
                refinementMeasurementPoints3D = convertDepthPointsTo3D(refinementFilteredPoints)
            }
        }
        
        // Compute combined center and shift both point clouds
        var allPoints: [SCNVector3] = primaryMeasurementPoints3D
        if let refPoints = refinementMeasurementPoints3D {
            allPoints.append(contentsOf: refPoints)
        }
        let combinedBbox = calculateBoundingBox(allPoints)
        let center = SCNVector3(
            (combinedBbox.min.x + combinedBbox.max.x) / 2.0,
            (combinedBbox.min.y + combinedBbox.max.y) / 2.0,
            (combinedBbox.min.z + combinedBbox.max.z) / 2.0
        )
        
        // Shift primary points
        for i in 0..<primaryMeasurementPoints3D.count {
            primaryMeasurementPoints3D[i] = SCNVector3(
                primaryMeasurementPoints3D[i].x - center.x,
                primaryMeasurementPoints3D[i].y - center.y,
                primaryMeasurementPoints3D[i].z - center.z
            )
        }
        
        // Shift refinement points if exist
        if var refPoints = refinementMeasurementPoints3D {
            for i in 0..<refPoints.count {
                refPoints[i] = SCNVector3(
                    refPoints[i].x - center.x,
                    refPoints[i].y - center.y,
                    refPoints[i].z - center.z
                )
            }
            refinementMeasurementPoints3D = refPoints
        }
        
        // Create primary point cloud and voxels with shifted points
        let primaryPointCloudGeometry = createPointCloudGeometry(from: primaryMeasurementPoints3D)
        let primaryPointCloudNode = SCNNode(geometry: primaryPointCloudGeometry)
        
        let (primaryVoxelGeometry, primaryVolumeInfo) = createVoxelGeometry(from: primaryMeasurementPoints3D, color: SCNVector3(0, 1, 1), refinementMask: refinementMeasurementPoints3D) // Cyan
        let primaryVoxelNodeInstance = SCNNode(geometry: primaryVoxelGeometry)
        
        // Update primary volume information
        DispatchQueue.main.async {
            self.totalVolume = primaryVolumeInfo.totalVolume
            self.voxelCount = primaryVolumeInfo.voxelCount
            self.voxelSize = primaryVolumeInfo.voxelSize
            self.voxelNode = primaryVoxelNodeInstance
        }
        
        scene.rootNode.addChildNode(primaryPointCloudNode)
        if showVoxels {
            scene.rootNode.addChildNode(primaryVoxelNodeInstance)
        }
        
        // Create refinement if exists
        var refinementPointCloudNode: SCNNode? = nil
        var refinementVoxelNodeInstance: SCNNode? = nil
        if let refPoints = refinementMeasurementPoints3D {
            // Create refinement point cloud and voxels
            let refinementPointCloudGeometry = createPointCloudGeometry(from: refPoints)
            refinementPointCloudNode = SCNNode(geometry: refinementPointCloudGeometry)
            
            let (refinementVoxelGeometry, refinementVolumeInfo) = createVoxelGeometry(from: refPoints, color: SCNVector3(0, 1, 0)) // Green
            refinementVoxelNodeInstance = SCNNode(geometry: refinementVoxelGeometry)
            
            // Update refinement volume information
            DispatchQueue.main.async {
                self.refinementVolume = refinementVolumeInfo.totalVolume
                self.refinementVoxelCount = refinementVolumeInfo.voxelCount
                self.refinementVoxelNode = refinementVoxelNodeInstance
            }
            
            scene.rootNode.addChildNode(refinementPointCloudNode!)
            if showRefinementVoxels {
                scene.rootNode.addChildNode(refinementVoxelNodeInstance!)
            }
        }
        
        // Add lighting
        setupLighting(scene: scene)
        
        // Setup camera using primary measurement coordinates
        setupCamera(scene: scene, pointCloud: primaryMeasurementPoints3D)
        
        return scene
    }
    
    private func convertDepthPointsTo3D(_ points: [DepthPoint]) -> [SCNVector3] {
        guard !points.isEmpty else { return [] }
        
        var measurementPoints3D: [SCNVector3] = []
        
        guard let intrinsics = cameraIntrinsics else {
            print("No camera intrinsics available")
            return []
        }
        
        // CORRECTION: Scale intrinsics from 4032x2268 to 640x360 resolution
        let resolutionScaleX: Float = 640.0 / 4032.0
        let resolutionScaleY: Float = 360.0 / 2268.0
        
        let correctedFx = intrinsics.fx * resolutionScaleX
        let correctedFy = intrinsics.fy * resolutionScaleY
        let correctedCx = intrinsics.cx * resolutionScaleX
        let correctedCy = intrinsics.cy * resolutionScaleY
        
        // Calculate average depth from all points
        let totalDepth = points.reduce(0.0) { $0 + $1.depth }
        let averageDepth = points.isEmpty ? 0.5 : totalDepth / Float(points.count)
        
        for point in points {
            let pixelX = point.x
            let pixelY = point.y
            let depthInMeters = point.depth
            
            let realWorldX = (pixelX - correctedCx) * averageDepth / correctedFx
            let realWorldY = (pixelY - correctedCy) * averageDepth / correctedFy
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
        
//        for i in 0..<measurementPoints3D.count {
//            measurementPoints3D[i] = SCNVector3(
//                measurementPoints3D[i].x - center.x,
//                measurementPoints3D[i].y - center.y,
//                measurementPoints3D[i].z - center.z
//            )
//        }
        
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
    
    private func createVoxelGeometry(from measurementPoints3D: [SCNVector3], color: SCNVector3 = SCNVector3(0, 1, 1), refinementMask: [SCNVector3]? = nil) -> (SCNGeometry, VoxelVolumeInfo) {
        guard !measurementPoints3D.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        let bbox = calculateBoundingBox(measurementPoints3D)
        let min = bbox.min
        let max = bbox.max
        
        let boundingBoxVolume = (max.x - min.x) * (max.y - min.y) * (max.z - min.z)
        
        let maxVoxels: Float = 1_000_000
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
        
        var surfaceVoxels = Set<String>()
        
        for point in measurementPoints3D {
            let vx = Int((point.x - min.x) / voxelSize)
            let vy = Int((point.y - min.y) / voxelSize)
            let vz = Int((point.z - min.z) / voxelSize)
            
            let clampedVx = Swift.max(0, Swift.min(gridX - 1, vx))
            let clampedVy = Swift.max(0, Swift.min(gridY - 1, vy))
            let clampedVz = Swift.max(0, Swift.min(gridZ - 1, vz))
            
            surfaceVoxels.insert("\(clampedVx),\(clampedVy),\(clampedVz)")
        }
        
        var filledVoxels = Set<String>()
        
        for z in 0..<gridZ {
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
            
            let hull = convexHull2D(layerSurface)
            
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
        
        filledVoxels.formUnion(surfaceVoxels)

        // Apply refinement mask if provided
        if let refinementPoints = refinementMask, !refinementPoints.isEmpty {
            // Create a set of X,Y coordinates from refinement points with tolerance
            let tolerance: Float = voxelSize * 1.5 // Allow some overlap tolerance
            var refinementXYSet = Set<String>()
            
            for point in refinementPoints {
                let gridX = Int((point.x - min.x) / voxelSize)
                let gridY = Int((point.y - min.y) / voxelSize)
                
                // Add neighboring grid cells within tolerance
                for dx in -1...1 {
                    for dy in -1...1 {
                        let adjX = gridX + dx
                        let adjY = gridY + dy
                        refinementXYSet.insert("\(adjX),\(adjY)")
                    }
                }
            }
            
            // Filter filledVoxels to only include those with X,Y in refinement mask
            let maskedVoxels = filledVoxels.filter { voxelKey in
                let components = voxelKey.split(separator: ",")
                let vx = components[0]
                let vy = components[1]
                return refinementXYSet.contains("\(vx),\(vy)")
            }
            
            filledVoxels = Set(maskedVoxels)
        }
        
        guard !filledVoxels.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize)
        let totalVolumeM3 = Double(filledVoxels.count) * singleVoxelVolume
        
        let volumeInfo = VoxelVolumeInfo(
            totalVolume: totalVolumeM3,
            voxelCount: filledVoxels.count,
            voxelSize: voxelSize
        )
        
        var voxelVertices: [SCNVector3] = []
        var voxelColors: [SCNVector3] = []
        
        let halfSize = voxelSize * 0.5
        
        for voxelKey in filledVoxels {
            let components = voxelKey.split(separator: ",")
            let vx = Int(components[0])!
            let vy = Int(components[1])!
            let vz = Int(components[2])!
            
            let centerX = min.x + (Float(vx) + 0.5) * voxelSize
            let centerY = min.y + (Float(vy) + 0.5) * voxelSize
            let centerZ = min.z + (Float(vz) + 0.5) * voxelSize
            
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
            
            for _ in 0..<8 {
                voxelColors.append(color) // Use the provided color
            }
        }
        
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
        
        var indices: [UInt32] = []
        let cubeIndices: [UInt32] = [
            0, 1, 2,  2, 3, 0,
            4, 5, 6,  6, 7, 4,
            0, 4, 7,  7, 3, 0,
            1, 5, 6,  6, 2, 1,
            3, 2, 6,  6, 7, 3,
            0, 1, 5,  5, 4, 0
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
        
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.transparency = 0.7
        geometry.materials = [material]
        
        return (geometry, volumeInfo)
    }
    
    private func convexHull2D(_ points: [(x: Int, y: Int)]) -> [(x: Int, y: Int)] {
        if points.count < 3 { return points }
        
        let uniquePoints = Array(Set(points.map { "\($0.x),\($0.y)" }))
            .compactMap { key -> (x: Int, y: Int)? in
                let parts = key.split(separator: ",")
                guard parts.count == 2,
                      let x = Int(parts[0]),
                      let y = Int(parts[1]) else { return nil }
                return (x: x, y: y)
            }
        
        if uniquePoints.count < 3 { return uniquePoints }
        
        var start = uniquePoints[0]
        for p in uniquePoints {
            if p.y < start.y || (p.y == start.y && p.x < start.x) {
                start = p
            }
        }
        
        let others = uniquePoints.filter { $0.x != start.x || $0.y != start.y }
        let sorted = others.sorted { a, b in
            let angleA = atan2(Double(a.y - start.y), Double(a.x - start.x))
            let angleB = atan2(Double(b.y - start.y), Double(b.x - start.x))
            return angleA < angleB
        }
        
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
        
        let bbox = calculateBoundingBox(measurementPoints3D)
        let depthRange = bbox.max.z - bbox.min.z

        var colors: [SCNVector3] = []
        for point in measurementPoints3D {
            let normalizedDepth = depthRange > 0 ? (point.z - bbox.min.z) / depthRange : 0
            let invertedDepth = 1.0 - normalizedDepth
            let color = depthToColor(invertedDepth)
            colors.append(color)
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
