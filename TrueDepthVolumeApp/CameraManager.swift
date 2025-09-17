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