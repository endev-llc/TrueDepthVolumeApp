//
//  DepthVisualization3DView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import SwiftUI
import SceneKit

// MARK: - 3D Depth Visualization View with Voxels
struct DepthVisualization3DView: View {
    let csvFileURL: URL
    let onDismiss: () -> Void
    var refinementMask: UIImage? = nil
    var refinementImageFrame: CGRect = .zero
    var refinementDepthImageSize: CGSize = .zero
    
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scene: SCNScene?
    @State private var totalVolume: Double = 0.0
    @State private var voxelCount: Int = 0
    @State private var voxelSize: Float = 0.0
    @State private var cameraIntrinsics: CameraIntrinsics? = nil
    @State private var showVoxels: Bool = true
    @State private var voxelNode: SCNNode?
    @State private var originalVoxelData: (filledVoxels: Set<String>, min: SCNVector3, max: SCNVector3, voxelSize: Float)?
    @State private var originalDepthPoints: [DepthPoint] = []
    
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
                                Text("Volume: \(String(format: "%.2f", totalVolume * 1_000_000)) cm^3")
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
            print("TARGET: Loaded camera intrinsics from CSV: fx=\(intrinsics.fx), fy=\(intrinsics.fy)")
        } else {
            print("WARNING: No camera intrinsics found in CSV")
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
        
        print("DATA: Parsed \(points.count) valid depth points from CSV")
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
        
        // Store original depth points for refinement coordinate mapping
        self.originalDepthPoints = points
        
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
        
        // Store original voxel data for refinement
        DispatchQueue.main.async {
            self.originalVoxelData = (filledVoxels: filledVoxels, min: min, max: max, voxelSize: voxelSize)
        }
        
        // Apply refinement mask if provided
        let finalVoxels = applyRefinementMask(to: filledVoxels, min: min, max: max, voxelSize: voxelSize)
        
        guard !finalVoxels.isEmpty else {
            return (SCNGeometry(), VoxelVolumeInfo(totalVolume: 0.0, voxelCount: 0, voxelSize: 0.0))
        }
        
        print("Final voxel count after refinement: \(finalVoxels.count)")
        
        // Calculate total volume using MEASUREMENT coordinates (accurate)
        let singleVoxelVolume = Double(voxelSize * voxelSize * voxelSize) // in cubic meters
        let totalVolumeM3 = Double(finalVoxels.count) * singleVoxelVolume
        
        print("Refined Total Volume: \(totalVolumeM3 * 1_000_000) cm^3")
        
        // Create volume info
        let volumeInfo = VoxelVolumeInfo(
            totalVolume: totalVolumeM3,
            voxelCount: finalVoxels.count,
            voxelSize: voxelSize
        )
        
        // Create geometry using the refined voxels
        return (createVoxelGeometry(from: finalVoxels, min: min, max: max, voxelSize: voxelSize), volumeInfo)
    }
    
    // MARK: - FIXED: Refinement Mask Application with Correct Coordinate Mapping
    private func applyRefinementMask(to voxels: Set<String>, min: SCNVector3, max: SCNVector3, voxelSize: Float) -> Set<String> {
        guard let refinementMask = refinementMask else {
            return voxels // No refinement, return all voxels
        }
        
        print("REFINEMENT: Filtering \(voxels.count) voxels with visual mask")
        
        // Extract mask pixel data
        let maskPixelData = extractMaskPixelData(from: refinementMask)
        
        // Get original data dimensions from stored depth points
        let originalMaxX = Int(ceil(originalDepthPoints.map { $0.x }.max() ?? 0))
        let originalMaxY = Int(ceil(originalDepthPoints.map { $0.y }.max() ?? 0))
        let originalWidth = originalMaxX + 1
        let originalHeight = originalMaxY + 1
        
        print("REFINEMENT: Original data dimensions: \(originalWidth) x \(originalHeight)")
        print("REFINEMENT: Mask dimensions: \(refinementMask.size)")
        
        var refinedVoxels = Set<String>()
        
        for voxelKey in voxels {
            let components = voxelKey.split(separator: ",")
            let vx = Int(components[0])!
            let vy = Int(components[1])!
            let vz = Int(components[2])!
            
            // Calculate voxel center in measurement space
            let centerX = min.x + (Float(vx) + 0.5) * voxelSize
            let centerY = min.y + (Float(vy) + 0.5) * voxelSize
            let centerZ = min.z + (Float(vz) + 0.5) * voxelSize
            
            // FIXED: Use a more direct approach - sample multiple points within each voxel
            // and check if ANY of them fall within the mask
            var isVoxelInMask = false
            
            // Sample 5x5 grid within the voxel for better accuracy
            for dx in 0..<5 {
                for dy in 0..<5 {
                    let sampleX = centerX + (Float(dx) - 2.0) * voxelSize * 0.2
                    let sampleY = centerY + (Float(dy) - 2.0) * voxelSize * 0.2
                    
                    if isVoxelSampleInMask(sampleX: sampleX, sampleY: sampleY,
                                         min: min, max: max,
                                         originalWidth: originalWidth, originalHeight: originalHeight,
                                         maskPixelData: maskPixelData, maskImage: refinementMask) {
                        isVoxelInMask = true
                        break
                    }
                }
                if isVoxelInMask { break }
            }
            
            if isVoxelInMask {
                refinedVoxels.insert(voxelKey)
            }
        }
        
        print("REFINEMENT: Kept \(refinedVoxels.count) voxels after mask filtering")
        return refinedVoxels
    }
    
    private func isVoxelSampleInMask(sampleX: Float, sampleY: Float, min: SCNVector3, max: SCNVector3,
                                   originalWidth: Int, originalHeight: Int,
                                   maskPixelData: [UInt8], maskImage: UIImage) -> Bool {
        guard let cgImage = maskImage.cgImage else { return false }
        
        let maskWidth = cgImage.width
        let maskHeight = cgImage.height
        
        // Convert 3D measurement coordinates back to original pixel coordinates
        // This reverses the 3D conversion process used in convertDepthPointsTo3D
        
        // STEP 1: Convert from measurement space to normalized coordinates
        let normalizedX = (sampleX - min.x) / (max.x - min.x)
        let normalizedY = (sampleY - min.y) / (max.y - min.y)
        
        // STEP 2: Map to original pixel coordinates
        let pixelX = normalizedX * Float(originalWidth)
        let pixelY = normalizedY * Float(originalHeight)
        
        // STEP 3: Apply the same rotation transformation used in original data processing
        // Original: (x,y) -> (originalHeight-1-y, x) for display coordinates
        let displayX = Int(Float(originalHeight - 1) - pixelY)
        let displayY = Int(pixelX)
        
        // STEP 4: Convert display coordinates to mask coordinates
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
    
    private func createVoxelGeometry(from voxels: Set<String>, min: SCNVector3, max: SCNVector3, voxelSize: Float) -> SCNGeometry {
        guard !voxels.isEmpty else { return SCNGeometry() }
        
        // Create geometry using MEASUREMENT coordinates for consistent positioning
        var voxelVertices: [SCNVector3] = []
        var voxelColors: [SCNVector3] = []
        
        let halfSize = voxelSize * 0.5
        
        for voxelKey in voxels {
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
        
        return geometry
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
