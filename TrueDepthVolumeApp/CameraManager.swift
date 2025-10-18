//
//  CameraManager.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import Foundation
import SwiftUI
import AVFoundation
import UIKit
import CoreGraphics

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
    @Published var croppedPhoto: UIImage?
    @Published var refinementMask: UIImage?
    @Published var refinementImageFrame: CGRect = .zero
    @Published var refinementDepthImageSize: CGSize = .zero
    private var initialCroppedCSV: URL?
    
    var errorMessage = ""
    var fileToShare: URL?

    private var latestDepthData: AVDepthData?
    private var currentDepthData: AVDepthData?
    private var currentPhotoData: Data?
    private var captureCompletion: ((Bool) -> Void)?
    var rawDepthData: AVDepthData? // Store the raw depth data for cropping
    private var cameraCalibrationData: AVCameraCalibrationData? // Store camera intrinsics
    var uploadedCSVData: [DepthPoint] = [] // Store uploaded CSV data for cropping
    
    // Store mask boundary points for plane-of-best-fit calculation
    var maskBoundaryPoints: [(x: Int, y: Int)] = []
    var maskDimensions: CGSize = .zero
    var boundaryDepthPoints: [DepthPoint] = []  // Boundary points with depth values for plane fitting

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
        
        // Create rotated dimensions to match camera capture orientation (90 degree rotation)
        let rotatedWidth = originalHeight  // Swap width and height like camera capture
        let rotatedHeight = originalWidth
        
        // Use percentile-based normalization for better contrast
        let depthValues = points.map { $0.depth }.filter { !$0.isNaN && !$0.isInfinite && $0 > 0 }
        guard !depthValues.isEmpty else { return nil }
        
        let sortedDepths = depthValues.sorted()
        let percentile5 = sortedDepths[Int(Float(sortedDepths.count) * 0.05)]
        let percentile95 = sortedDepths[Int(Float(sortedDepths.count) * 0.95)]
        let depthRange = percentile95 - percentile5
        
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
            
            // Clamp to percentile range
            let clampedDepth = max(percentile5, min(percentile95, point.depth))
            let normalizedDepth = depthRange > 0 ? (clampedDepth - percentile5) / depthRange : 0
            let invertedDepth = 1.0 - normalizedDepth
            
            // Apply gamma correction for enhanced contrast
            let gamma: Float = 0.5 // Lower gamma enhances contrast
            let enhancedDepth = pow(invertedDepth, gamma)
            
            let color = interpolateColor(colormap: jetColormap, t: enhancedDepth)
            
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
    
    // MARK: - ULTRA-FAST: Skip expansion entirely (mask is already good from MobileSAM)
    private func simpleExpandMask(_ maskImage: UIImage) -> UIImage? {
        guard let cgImage = maskImage.cgImage,
              let depthImage = self.capturedDepthImage else {
            return maskImage
        }
        
        // Calculate expansion radius by analyzing actual depth gradients
        let expansionRadius = calculateDepthBasedExpansionRadius(
            maskImage: maskImage,
            depthImage: depthImage
        )
        
        guard expansionRadius > 0 else {
            print("No expansion needed - mask already covers gradient zone")
            return maskImage
        }
        
        print("Expanding mask by \(expansionRadius) pixels based on depth gradient analysis")
        
        let width = cgImage.width
        let height = cgImage.height
        let totalPixels = width * height
        
        // Extract mask data
        var maskData = [UInt8](repeating: 0, count: totalPixels * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Create binary mask array
        var isMask = [Bool](repeating: false, count: totalPixels)
        for i in 0..<totalPixels {
            isMask[i] = maskData[i * 4] > 128
        }
        
        // Find boundary pixels
        var boundaryPixels: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if isMask[index] {
                    let hasNonMaskNeighbor =
                        (x > 0 && !isMask[index - 1]) ||
                        (x < width - 1 && !isMask[index + 1]) ||
                        (y > 0 && !isMask[index - width]) ||
                        (y < height - 1 && !isMask[index + width])
                    
                    if hasNonMaskNeighbor {
                        boundaryPixels.append(index)
                    }
                }
            }
        }
        
        // Perform dilation
        var expandedMask = isMask
        let radiusSquared = expansionRadius * expansionRadius
        
        for boundaryIndex in boundaryPixels {
            let by = boundaryIndex / width
            let bx = boundaryIndex % width
            
            let minY = max(0, by - expansionRadius)
            let maxY = min(height - 1, by + expansionRadius)
            let minX = max(0, bx - expansionRadius)
            let maxX = min(width - 1, bx + expansionRadius)
            
            for y in minY...maxY {
                for x in minX...maxX {
                    let dx = x - bx
                    let dy = y - by
                    let distSquared = dx * dx + dy * dy
                    
                    if distSquared <= radiusSquared {
                        expandedMask[y * width + x] = true
                    }
                }
            }
        }
        
        // Create expanded mask image
        var expandedMaskData = [UInt8](repeating: 0, count: totalPixels * 4)
        for i in 0..<totalPixels {
            if expandedMask[i] {
                expandedMaskData[i * 4] = 139
                expandedMaskData[i * 4 + 1] = 69
                expandedMaskData[i * 4 + 2] = 19
                expandedMaskData[i * 4 + 3] = 255
            }
        }
        
        guard let expandedContext = CGContext(
            data: &expandedMaskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let expandedCGImage = expandedContext.makeImage() else {
            return maskImage
        }
        
        return UIImage(cgImage: expandedCGImage)
    }

    // MARK: - Calculate Expansion Radius from Actual Depth Data
    private func calculateDepthBasedExpansionRadius(maskImage: UIImage, depthImage: UIImage) -> Int {
        guard let maskCGImage = maskImage.cgImage,
              let depthCGImage = depthImage.cgImage else {
            return 0
        }
        
        let width = maskCGImage.width
        let height = maskCGImage.height
        let totalPixels = width * height
        
        // Extract mask data
        var maskData = [UInt8](repeating: 0, count: totalPixels * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var maskContext = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        maskContext?.draw(maskCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Extract depth visualization data (contains the color-coded depth)
        var depthData = [UInt8](repeating: 0, count: totalPixels * 4)
        var depthContext = CGContext(
            data: &depthData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        depthContext?.draw(depthCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Find mask boundary pixels
        var boundaryPixels: [(x: Int, y: Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                if maskData[index] > 128 {
                    // Check if boundary
                    let hasNonMaskNeighbor =
                        (x > 0 && maskData[(y * width + x - 1) * 4] <= 128) ||
                        (x < width - 1 && maskData[(y * width + x + 1) * 4] <= 128) ||
                        (y > 0 && maskData[((y - 1) * width + x) * 4] <= 128) ||
                        (y < height - 1 && maskData[((y + 1) * width + x) * 4] <= 128)
                    
                    if hasNonMaskNeighbor {
                        boundaryPixels.append((x, y))
                    }
                }
            }
        }
        
        guard !boundaryPixels.isEmpty else { return 0 }
        
        // Sample boundary pixels to measure gradient distance
        let sampleSize = min(100, boundaryPixels.count)
        let stepSize = max(1, boundaryPixels.count / sampleSize)
        var gradientDistances: [Int] = []
        
        for i in stride(from: 0, to: boundaryPixels.count, by: stepSize) {
            let (bx, by) = boundaryPixels[i]
            let boundaryIndex = (by * width + bx) * 4
            
            // Get boundary color (represents depth)
            let boundaryR = depthData[boundaryIndex]
            let boundaryG = depthData[boundaryIndex + 1]
            let boundaryB = depthData[boundaryIndex + 2]
            
            // Cast rays outward in 8 directions to find gradient extent
            let directions = [(1,0), (-1,0), (0,1), (0,-1), (1,1), (1,-1), (-1,1), (-1,-1)]
            
            for (dx, dy) in directions {
                var distance = 0
                var x = bx
                var y = by
                var prevColorDistance: Float = 0
                
                // Walk outward until color stabilizes (gradient ends)
                for _ in 0..<50 { // Max search distance
                    x += dx
                    y += dy
                    
                    if x < 0 || x >= width || y < 0 || y >= height { break }
                    
                    let currentIndex = (y * width + x) * 4
                    let r = depthData[currentIndex]
                    let g = depthData[currentIndex + 1]
                    let b = depthData[currentIndex + 2]
                    
                    // Calculate color distance from boundary
                    let dr = Float(Int(r) - Int(boundaryR))
                    let dg = Float(Int(g) - Int(boundaryG))
                    let db = Float(Int(b) - Int(boundaryB))
                    let colorDistance = sqrt(dr*dr + dg*dg + db*db)
                    
                    // If color change rate drops significantly, gradient has ended
                    if distance > 0 {
                        let changeRate = abs(colorDistance - prevColorDistance)
                        if changeRate < 2.0 && colorDistance > 50 { // Gradient stabilized
                            break
                        }
                    }
                    
                    prevColorDistance = colorDistance
                    distance += 1
                }
                
                if distance > 0 {
                    gradientDistances.append(distance)
                }
            }
        }
        
        guard !gradientDistances.isEmpty else { return 10 } // Fallback minimum
        
        gradientDistances.sort()
        // Use median instead of 75th percentile for more conservative expansion
        let medianIndex = gradientDistances.count / 2
        let expansionRadius = gradientDistances[medianIndex]

        print("Analyzed \(gradientDistances.count) gradient measurements")
        print("Gradient distances - min: \(gradientDistances.first!), median: \(expansionRadius), 75th: \(gradientDistances[Int(Float(gradientDistances.count) * 0.75)]), max: \(gradientDistances.last!)")
        
        return expansionRadius
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
        
        // Collect all valid depth values for percentile-based normalization
        var validDepths: [Float] = []
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                let depthValue = floatBuffer[pixelIndex]
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                    validDepths.append(depthValue)
                }
            }
        }
        
        guard !validDepths.isEmpty else { return nil }
        
        // Use percentile-based normalization for better contrast
        validDepths.sort()
        let percentile5 = validDepths[Int(Float(validDepths.count) * 0.05)]
        let percentile95 = validDepths[Int(Float(validDepths.count) * 0.95)]
        let depthRange = percentile95 - percentile5
        
        // Create CGImage with rotated dimensions (90 degree clockwise rotation)
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
                
                if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 && depthRange > 0 {
                    // Clamp to percentile range
                    let clampedDepth = max(percentile5, min(percentile95, depthValue))
                    let normalizedDepth = (clampedDepth - percentile5) / depthRange
                    let invertedDepth = 1.0 - normalizedDepth // Closer = hot, farther = cool
                    
                    // Apply gamma correction for enhanced contrast
                    let gamma: Float = 0.5 // Lower gamma enhances contrast
                    let enhancedDepth = pow(invertedDepth, gamma)
                    
                    color = interpolateColor(colormap: jetColormap, t: enhancedDepth)
                }
                
                // Rotate 90 degree counterclockwise: (x,y) -> (originalHeight-1-y, x)
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
    
    // MARK: - Mask-based Cropping Function (Add this to CameraManager.swift)
    func cropDepthDataWithMask(_ maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize, skipExpansion: Bool = false) {
        
        // Conditionally apply expansion based on whether pen was used
        let finalMask: UIImage
        if skipExpansion {
            print("⏭️ Skipping mask expansion - user drew mask with pen tool")
            finalMask = maskImage
        } else {
            print("🔄 Applying smart expansion - mask from tap-to-apply only")
            finalMask = simpleExpandMask(maskImage) ?? maskImage
        }
        
        // EXTRACT AND PRINT THE ACTUAL PERIMETER POINTS FROM THE MASK
        extractAndPrintMaskBoundary(finalMask, depthImageSize: depthImageSize)
        
        // Save the cropped photo using the mask
        if let photo = capturedPhoto {
            DispatchQueue.global(qos: .userInitiated).async {
                let croppedPhoto = self.cropPhoto(photo, withMask: finalMask, imageFrame: imageFrame)
                DispatchQueue.main.async {
                    self.croppedPhoto = croppedPhoto
                }
            }
        }
        
        if !uploadedCSVData.isEmpty {
            cropUploadedCSVWithMask(finalMask, imageFrame: imageFrame, depthImageSize: depthImageSize)
        } else if let depthData = rawDepthData {
            saveDepthDataToFileWithMask(depthData: depthData, maskImage: finalMask, imageFrame: imageFrame, depthImageSize: depthImageSize)
        } else {
            presentError("No depth data available for cropping.")
            return
        }
        
        DispatchQueue.main.async {
            self.hasOutline = true
        }
    }

    // Add this new function to crop the photo with the mask
    private func cropPhoto(_ photo: UIImage, withMask maskImage: UIImage, imageFrame: CGRect) -> UIImage? {
        guard let maskCGImage = maskImage.cgImage,
              let photoCGImage = photo.cgImage else { return nil }
        
        let size = photo.size
        
        UIGraphicsBeginImageContextWithOptions(size, false, photo.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // Draw the photo
        photo.draw(at: .zero)
        
        // Create mask from the brown mask image
        context.setBlendMode(.destinationIn)
        
        // Draw mask
        UIImage(cgImage: maskCGImage).draw(in: CGRect(origin: .zero, size: size), blendMode: .destinationIn, alpha: 1.0)
        
        let croppedPhoto = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return croppedPhoto
    }

    // MARK: - FIXED: Refinement Function (no more 70-second hang)
    func refineWithSecondaryMask(_ secondaryMask: UIImage, imageFrame: CGRect, depthImageSize: CGSize, primaryCroppedCSV: URL, skipExpansion: Bool = false) {
        // Refinement masks - only expand if not user-drawn
        let finalMask: UIImage
        if skipExpansion {
            print("⏭️ Skipping refinement mask expansion - user drew mask with pen tool")
            finalMask = secondaryMask
        } else {
            print("ℹ️ Refinement mask from tap-to-apply (already precise, no expansion needed)")
            finalMask = secondaryMask
        }
        
        // Store the refinement mask for the 3D view
        DispatchQueue.main.async {
            self.refinementMask = finalMask
            self.refinementImageFrame = imageFrame
            self.refinementDepthImageSize = depthImageSize
        }
    }

    private func cropUploadedCSVWithMask(_ maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize) {
        guard !uploadedCSVData.isEmpty else { return }
        
        // Show processing indicator
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "depth_data_masked_\(timestamp).csv"
            
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
                
                // Preserve camera intrinsics from original file
                if let originalFileURL = self.fileToShare {
                    let originalContent = try String(contentsOf: originalFileURL)
                    let originalLines = originalContent.components(separatedBy: .newlines)
                    
                    for line in originalLines {
                        if line.hasPrefix("#") {
                            csvLines.append(line)
                        }
                    }
                }
                
                csvLines.append("# Cropped using AI mask segmentation")
                
                var croppedPixelCount = 0
                let maskPixelData = self.extractMaskPixelData(from: maskImage)
                
                // Get original data dimensions
                let originalMaxX = Int(ceil(self.uploadedCSVData.map { $0.x }.max() ?? 0))
                let originalMaxY = Int(ceil(self.uploadedCSVData.map { $0.y }.max() ?? 0))
                let originalWidth = originalMaxX + 1
                let originalHeight = originalMaxY + 1
                
                print("Processing \(self.uploadedCSVData.count) points with mask...")
                
                for point in self.uploadedCSVData {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    
                    // Transform to display coordinates (same rotation as camera capture)
                    let displayX = originalHeight - 1 - y
                    let displayY = x
                    
                    // Check if this point falls within any mask region
                    if self.isPointInMask(displayX: displayX, displayY: displayY,
                                       originalWidth: originalWidth, originalHeight: originalHeight,
                                       maskPixelData: maskPixelData, maskImage: maskImage) {
                        csvLines.append("\(point.x),\(point.y),\(String(format: "%.6f", point.depth))")
                        croppedPixelCount += 1
                    }
                }
                
                let csvContent = csvLines.joined(separator: "\n")
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                print("Successfully cropped \(croppedPixelCount) points from \(self.uploadedCSVData.count) total points using AI mask")
                
                DispatchQueue.main.async {
                    self.lastSavedFileName = fileName
                    self.croppedFileToShare = fileURL
                    self.isProcessing = false
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.presentError("Failed to save masked CSV: \(error.localizedDescription)")
                    self.isProcessing = false
                }
            }
        }
    }

    private func saveDepthDataToFileWithMask(depthData: AVDepthData, maskImage: UIImage, imageFrame: CGRect, depthImageSize: CGSize) {
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
        let fileName = "depth_data_masked_\(timestamp).csv"
        
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
            
            csvLines.append("# Cropped using AI mask segmentation")
            
            var croppedPixelCount = 0
            let maskPixelData = extractMaskPixelData(from: maskImage)
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = y * (bytesPerRow / MemoryLayout<Float32>.stride) + x
                    let depthValue = floatBuffer[pixelIndex]
                    
                    // Transform to display coordinates
                    let displayX = height - 1 - y
                    let displayY = x
                    
                    // Check if this point falls within any mask region
                    if isPointInMask(displayX: displayX, displayY: displayY,
                                   originalWidth: width, originalHeight: height,
                                   maskPixelData: maskPixelData, maskImage: maskImage) {
                        csvLines.append("\(x),\(y),\(String(format: "%.6f", depthValue))")
                        croppedPixelCount += 1
                    }
                }
            }
            
            let csvContent = csvLines.joined(separator: "\n")
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            print("Successfully cropped \(croppedPixelCount) points using AI mask")
            
            DispatchQueue.main.async {
                self.lastSavedFileName = fileName
                self.croppedFileToShare = fileURL
            }
            
        } catch {
            self.presentError("Failed to save masked depth data: \(error.localizedDescription)")
        }
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
    
    // MARK: - Mask Boundary Detection (ACTUAL PERIMETER POINTS)
    private func extractAndPrintMaskBoundary(_ maskImage: UIImage, depthImageSize: CGSize) {
        guard let cgImage = maskImage.cgImage else { return }
        
        let width = cgImage.width
        let height = cgImage.height
        
        print("\n🎯 EXTRACTING ACTUAL PERIMETER POINTS FROM MASK")
        print(String(repeating: "=", count: 60))
        print("Mask dimensions: \(width) x \(height)")
        
        // Extract mask data
        var maskData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Find boundary points (points in mask with at least one neighbor out of mask)
        var boundaryPoints: [(x: Int, y: Int)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let isInMask = maskData[index] > 128
                
                if isInMask {
                    // Check 4-connected neighbors
                    var hasExternalNeighbor = false
                    
                    // Check left
                    if x > 0 {
                        let leftIndex = (y * width + (x - 1)) * 4
                        if maskData[leftIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true // Edge of image
                    }
                    
                    // Check right
                    if x < width - 1 {
                        let rightIndex = (y * width + (x + 1)) * 4
                        if maskData[rightIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true // Edge of image
                    }
                    
                    // Check top
                    if y > 0 {
                        let topIndex = ((y - 1) * width + x) * 4
                        if maskData[topIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true // Edge of image
                    }
                    
                    // Check bottom
                    if y < height - 1 {
                        let bottomIndex = ((y + 1) * width + x) * 4
                        if maskData[bottomIndex] <= 128 {
                            hasExternalNeighbor = true
                        }
                    } else {
                        hasExternalNeighbor = true // Edge of image
                    }
                    
                    if hasExternalNeighbor {
                        boundaryPoints.append((x: x, y: y))
                    }
                }
            }
        }
        
        print("\n📊 MASK BOUNDARY STATISTICS:")
        print("Total boundary points found: \(boundaryPoints.count)")
        
        print("\n📍 BOUNDARY POINTS (Display Coordinates):")
        print("First 50 points:")
        for (index, point) in boundaryPoints.prefix(50).enumerated() {
            print("  Point \(index + 1): (\(point.x), \(point.y))")
        }
        
        if boundaryPoints.count > 50 {
            print("  ... (\(boundaryPoints.count - 50) more points)")
        }
        
        // STORE BOUNDARY POINTS FOR PLANE-OF-BEST-FIT CALCULATION
        self.maskBoundaryPoints = boundaryPoints
        self.maskDimensions = CGSize(width: width, height: height)
        print("\n✅ Stored \(boundaryPoints.count) boundary points for plane fitting")
        
        // NOW CONVERT TO DEPTH POINTS WITH Z VALUES
        print("\n🔄 CONVERTING BOUNDARY POINTS TO DEPTH COORDINATES...")
        extractBoundaryDepthPoints(boundaryPoints: boundaryPoints, maskWidth: width, maskHeight: height)
        
        print(String(repeating: "=", count: 60) + "\n")
    }
    
    private func extractBoundaryDepthPoints(boundaryPoints: [(x: Int, y: Int)], maskWidth: Int, maskHeight: Int) {
        var depthPoints: [DepthPoint] = []
        
        // Determine original depth data dimensions
        var originalWidth: Int = 0
        var originalHeight: Int = 0
        
        if !uploadedCSVData.isEmpty {
            // Get dimensions from uploaded CSV
            let maxX = Int(ceil(uploadedCSVData.map { $0.x }.max() ?? 0))
            let maxY = Int(ceil(uploadedCSVData.map { $0.y }.max() ?? 0))
            originalWidth = maxX + 1
            originalHeight = maxY + 1
            
            print("Using uploaded CSV data: \(originalWidth) x \(originalHeight)")
            
            // Create a lookup map for fast depth access
            var depthMap: [String: Float] = [:]
            for point in uploadedCSVData {
                let key = "\(Int(point.x)),\(Int(point.y))"
                depthMap[key] = point.depth
            }
            
            // Convert each boundary point
            for boundaryPoint in boundaryPoints {
                // Convert mask coordinates to original depth coordinates
                // Reverse the rotation: displayX = originalHeight - 1 - y, displayY = x
                let originalY = originalHeight - 1 - Int((Float(boundaryPoint.x) / Float(maskWidth)) * Float(originalHeight))
                let originalX = Int((Float(boundaryPoint.y) / Float(maskHeight)) * Float(originalWidth))
                
                // Get depth value
                let key = "\(originalX),\(originalY)"
                if let depth = depthMap[key] {
                    depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depth))
                }
            }
            
        } else if let depthData = rawDepthData {
            // Convert depth data if needed
            let processedDepthData: AVDepthData
            if depthData.depthDataType == kCVPixelFormatType_DisparityFloat16 ||
               depthData.depthDataType == kCVPixelFormatType_DisparityFloat32 {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            } else {
                do {
                    processedDepthData = try depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
                } catch {
                    print("Failed to convert depth data")
                    return
                }
            }
            
            let depthMap = processedDepthData.depthDataMap
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
            
            originalWidth = CVPixelBufferGetWidth(depthMap)
            originalHeight = CVPixelBufferGetHeight(depthMap)
            let floatBuffer = CVPixelBufferGetBaseAddress(depthMap)!.bindMemory(to: Float32.self, capacity: originalWidth * originalHeight)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            
            print("Using raw depth data: \(originalWidth) x \(originalHeight)")
            
            // Convert each boundary point
            for boundaryPoint in boundaryPoints {
                // Convert mask coordinates to original depth coordinates
                // Reverse the rotation: displayX = originalHeight - 1 - y, displayY = x
                let originalY = originalHeight - 1 - Int((Float(boundaryPoint.x) / Float(maskWidth)) * Float(originalHeight))
                let originalX = Int((Float(boundaryPoint.y) / Float(maskHeight)) * Float(originalWidth))
                
                // Get depth value
                if originalX >= 0 && originalX < originalWidth && originalY >= 0 && originalY < originalHeight {
                    let pixelIndex = originalY * (bytesPerRow / MemoryLayout<Float32>.stride) + originalX
                    let depthValue = floatBuffer[pixelIndex]
                    
                    if !depthValue.isNaN && !depthValue.isInfinite && depthValue > 0 {
                        depthPoints.append(DepthPoint(x: Float(originalX), y: Float(originalY), depth: depthValue))
                    }
                }
            }
        }
        
        // Store for use by 3D visualization
        self.boundaryDepthPoints = depthPoints
        print("✅ Successfully converted \(depthPoints.count) boundary points with depth values")
    }
}
