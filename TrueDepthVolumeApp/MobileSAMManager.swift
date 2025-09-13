//
//  MobileSAMManager.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/11/25.
//

import CoreML
import UIKit
import SwiftUI

class MobileSAMManager: ObservableObject {
    private let imageEncoder: mobile_sam_image_encoder
    private let promptEncoder: mobile_sam_prompt_encoder_working
    private let maskDecoder: mobile_sam_mask_decoder
    
    @Published var currentMask: UIImage?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private var currentImageSize: CGSize = .zero
    private var modelImageSize: CGSize = CGSize(width: 1024, height: 1024) // SAM typically uses 1024x1024
    
    init() throws {
        print("🔧 [INIT] Starting MobileSAMManager initialization...")
        
        do {
            print("🔧 [INIT] Loading image encoder model...")
            let imageEncoderConfig = MLModelConfiguration()
            print("🔧 [INIT] Image encoder config: \(imageEncoderConfig)")
            imageEncoder = try mobile_sam_image_encoder(configuration: imageEncoderConfig)
            print("✅ [INIT] Image encoder loaded successfully")
            
            print("🔧 [INIT] Loading prompt encoder model...")
            let promptEncoderConfig = MLModelConfiguration()
            print("🔧 [INIT] Prompt encoder config: \(promptEncoderConfig)")
            promptEncoder = try mobile_sam_prompt_encoder_working(configuration: promptEncoderConfig)
            print("✅ [INIT] Prompt encoder loaded successfully")
            
            print("🔧 [INIT] Loading mask decoder model...")
            let maskDecoderConfig = MLModelConfiguration()
            print("🔧 [INIT] Mask decoder config: \(maskDecoderConfig)")
            maskDecoder = try mobile_sam_mask_decoder(configuration: maskDecoderConfig)
            print("✅ [INIT] Mask decoder loaded successfully")
            
            print("✅ [INIT] All models loaded successfully!")
            print("🔧 [INIT] Model image size set to: \(modelImageSize)")
            
        } catch {
            print("❌ [INIT] Failed to load models: \(error)")
            print("❌ [INIT] Error details: \(error.localizedDescription)")
            throw error
        }
    }
    
    func segment(image: UIImage, clickPoint: CGPoint) {
        print("\n🚀 [SEGMENT] Starting segmentation process...")
        print("🚀 [SEGMENT] Input image size: \(image.size)")
        print("🚀 [SEGMENT] Click point: \(clickPoint)")
        
        isProcessing = true
        errorMessage = nil
        currentMask = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()
            print("⏱️ [SEGMENT] Background processing started at: \(startTime)")
            
            do {
                guard let self = self else {
                    print("❌ [SEGMENT] Self is nil, aborting")
                    return
                }
                
                print("🔧 [SEGMENT] Storing original image size...")
                // Store original image size
                self.currentImageSize = image.size
                print("🔧 [SEGMENT] Current image size stored: \(self.currentImageSize)")
                
                print("🔧 [SEGMENT] Converting UIImage to CVPixelBuffer...")
                // Convert UIImage to CVPixelBuffer
                guard let pixelBuffer = self.imageToPixelBuffer(image: image) else {
                    print("❌ [SEGMENT] Image to pixel buffer conversion failed")
                    throw SAMError.imageConversionFailed
                }
                print("✅ [SEGMENT] CVPixelBuffer created successfully")
                print("🔧 [SEGMENT] PixelBuffer dimensions: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
                
                print("🔧 [SEGMENT] Converting click point to model coordinates...")
                // Convert click point to model coordinates
                let modelPoint = self.convertToModelCoordinates(
                    point: clickPoint,
                    imageSize: image.size,
                    modelSize: self.modelImageSize
                )
                print("🔧 [SEGMENT] Model coordinates: \(modelPoint)")
                
                print("🔧 [SEGMENT] Performing ML segmentation...")
                let mask = try self.performSegmentation(
                    pixelBuffer: pixelBuffer,
                    clickPoint: modelPoint
                )
                print("✅ [SEGMENT] ML segmentation completed")
                print("🔧 [SEGMENT] Mask shape: \(mask.shape)")
                
                print("🔧 [SEGMENT] Converting mask to UIImage...")
                // Convert mask to UIImage
                let maskImage = self.maskToUIImage(mask: mask, originalSize: image.size)
                print("✅ [SEGMENT] Mask converted to UIImage: \(maskImage != nil)")
                
                let endTime = CFAbsoluteTimeGetCurrent()
                let totalTime = endTime - startTime
                print("⏱️ [SEGMENT] Total processing time: \(totalTime) seconds")
                
                DispatchQueue.main.async {
                    print("🔧 [SEGMENT] Updating UI on main thread...")
                    self.currentMask = maskImage
                    self.isProcessing = false
                    print("✅ [SEGMENT] UI updated successfully")
                }
                
            } catch {
                print("❌ [SEGMENT] Error during segmentation: \(error)")
                print("❌ [SEGMENT] Error localized description: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    print("🔧 [SEGMENT] Updating error state on main thread...")
                    self?.errorMessage = error.localizedDescription
                    self?.isProcessing = false
                    print("✅ [SEGMENT] Error state updated")
                }
            }
        }
    }

    private func performSegmentation(pixelBuffer: CVPixelBuffer, clickPoint: CGPoint) throws -> MLMultiArray {
        print("\n🧠 [ML] Starting ML model inference pipeline...")
        
        print("🔧 [ML] Converting CVPixelBuffer to MLMultiArray...")
        // Convert CVPixelBuffer to MLMultiArray first
        guard let imageArray = pixelBufferToMLMultiArray(pixelBuffer: pixelBuffer) else {
            print("❌ [ML] CVPixelBuffer to MLMultiArray conversion failed")
            throw SAMError.imageConversionFailed
        }
        print("✅ [ML] Image array created successfully")
        print("🔧 [ML] Image array shape: \(imageArray.shape)")
        
        // 1. Encode image
        print("\n🔧 [ML] Step 1: Running image encoder...")
        let imageInput = mobile_sam_image_encoderInput(image: imageArray)
        print("🔧 [ML] Image encoder input created")
        
        let imageEncoderStart = CFAbsoluteTimeGetCurrent()
        let imageOutput = try imageEncoder.prediction(input: imageInput)
        let imageEncoderTime = CFAbsoluteTimeGetCurrent() - imageEncoderStart
        
        print("✅ [ML] Image encoder completed in \(imageEncoderTime) seconds")
        print("🔧 [ML] Image embeddings shape: \(imageOutput.image_embeddings.shape)")
        
        // 2. Encode single point prompt
        print("\n🔧 [ML] Step 2: Setting up prompt encoder inputs...")
        
        print("🔧 [ML] Creating point coordinates array...")
        let pointCoords = try MLMultiArray(shape: [1, 2, 2], dataType: .float32)
        print("🔧 [ML] Point coords shape: \(pointCoords.shape)")
        
        print("🔧 [ML] Creating point labels array...")
        let pointLabels = try MLMultiArray(shape: [1, 2], dataType: .float32)
        print("🔧 [ML] Point labels shape: \(pointLabels.shape)")

        // Set the actual click point
        print("🔧 [ML] Setting click point coordinates: \(clickPoint)")
        pointCoords[[0, 0, 0] as [NSNumber]] = NSNumber(value: clickPoint.x)
        pointCoords[[0, 0, 1] as [NSNumber]] = NSNumber(value: clickPoint.y)
        pointLabels[[0, 0] as [NSNumber]] = NSNumber(value: 1.0) // Positive click
        print("🔧 [ML] Point 1 set: (\(clickPoint.x), \(clickPoint.y)) with label 1.0")

        // Try setting second point to same location with different label
        pointCoords[[0, 1, 0] as [NSNumber]] = NSNumber(value: clickPoint.x)
        pointCoords[[0, 1, 1] as [NSNumber]] = NSNumber(value: clickPoint.y)
        pointLabels[[0, 1] as [NSNumber]] = NSNumber(value: 0.0) // Try 0.0 instead of -1.0
        print("🔧 [ML] Point 2 set: (\(clickPoint.x), \(clickPoint.y)) with label 0.0")

        // Create empty boxes input
        print("🔧 [ML] Creating empty boxes array...")
        let boxes = try MLMultiArray(shape: [1, 1, 4], dataType: .float32)
        print("🔧 [ML] Boxes shape: \(boxes.shape)")
        boxes[[0, 0, 0] as [NSNumber]] = NSNumber(value: 0.0)
        boxes[[0, 0, 1] as [NSNumber]] = NSNumber(value: 0.0)
        boxes[[0, 0, 2] as [NSNumber]] = NSNumber(value: 0.0)
        boxes[[0, 0, 3] as [NSNumber]] = NSNumber(value: 0.0)
        print("🔧 [ML] Boxes set to all zeros")

        // Create empty masks input
        print("🔧 [ML] Creating empty masks array...")
        let masks = try MLMultiArray(shape: [1, 1, 256, 256], dataType: .float32)
        print("🔧 [ML] Masks shape: \(masks.shape)")
        print("🔧 [ML] Masks initialized to zeros")

        print("🔧 [ML] Creating prompt encoder input...")
        let promptInput = mobile_sam_prompt_encoder_workingInput(
            points_coords: pointCoords,
            point_labels: pointLabels,
            boxes_1: boxes,
            masks: masks
        )
        print("🔧 [ML] Prompt encoder input created")
        
        print("🔧 [ML] Running prompt encoder...")
        let promptEncoderStart = CFAbsoluteTimeGetCurrent()
        let promptOutput = try promptEncoder.prediction(input: promptInput)
        let promptEncoderTime = CFAbsoluteTimeGetCurrent() - promptEncoderStart
        
        print("✅ [ML] Prompt encoder completed in \(promptEncoderTime) seconds")
        print("🔧 [ML] Prompt output var_145 shape: \(promptOutput.var_145.shape)")
        print("🔧 [ML] Prompt output var_215 shape: \(promptOutput.var_215.shape)")
        
        // 3. Decode mask
        print("\n🔧 [ML] Step 3: Setting up mask decoder...")
        
        print("🔧 [ML] Processing sparse embeddings...")
        let fullSparseEmbeddings = promptOutput.var_145
        print("🔧 [ML] Full sparse embeddings shape: \(fullSparseEmbeddings.shape)")
        
        let truncatedSparseEmbeddings = try MLMultiArray(shape: [1, 3, 256], dataType: .float32)
        print("🔧 [ML] Truncated sparse embeddings shape: \(truncatedSparseEmbeddings.shape)")

        // Copy only the first 3 embeddings
        print("🔧 [ML] Copying first 3 embeddings...")
        for i in 0..<3 {
            for j in 0..<256 {
                let sourceIndex = [0, i, j] as [NSNumber]
                let targetIndex = [0, i, j] as [NSNumber]
                truncatedSparseEmbeddings[targetIndex] = fullSparseEmbeddings[sourceIndex]
            }
        }
        print("✅ [ML] Sparse embeddings truncated and copied")

        print("🔧 [ML] Creating mask decoder input...")
        let decoderInput = mobile_sam_mask_decoderInput(
            image_embeddings: imageOutput.image_embeddings,
            sparse_embeddings: truncatedSparseEmbeddings,
            dense_embeddings: promptOutput.var_215
        )
        print("🔧 [ML] Decoder input created")
        print("🔧 [ML] Image embeddings shape: \(imageOutput.image_embeddings.shape)")
        print("🔧 [ML] Sparse embeddings shape: \(truncatedSparseEmbeddings.shape)")
        print("🔧 [ML] Dense embeddings shape: \(promptOutput.var_215.shape)")
        
        print("🔧 [ML] Running mask decoder...")
        let maskDecoderStart = CFAbsoluteTimeGetCurrent()
        let decoderOutput = try maskDecoder.prediction(input: decoderInput)
        let maskDecoderTime = CFAbsoluteTimeGetCurrent() - maskDecoderStart
        
        print("✅ [ML] Mask decoder completed in \(maskDecoderTime) seconds")
        print("🔧 [ML] Output masks shape: \(decoderOutput.masks.shape)")
        
        // Log some statistics about the mask
        let maskArray = decoderOutput.masks
        var positiveCount = 0
        var negativeCount = 0
        var zeroCount = 0
        
        for i in 0..<maskArray.count {
            let value = maskArray[i].floatValue
            if value > 0.5 {
                positiveCount += 1
            } else if value < -0.5 {
                negativeCount += 1
            } else {
                zeroCount += 1
            }
        }
        
        print("🔧 [ML] Mask statistics:")
        print("🔧 [ML] - Positive values (>0.5): \(positiveCount)")
        print("🔧 [ML] - Negative values (<-0.5): \(negativeCount)")
        print("🔧 [ML] - Near-zero values: \(zeroCount)")
        print("🔧 [ML] - Total values: \(maskArray.count)")
        
        return decoderOutput.masks
    }
    
    private func pixelBufferToMLMultiArray(pixelBuffer: CVPixelBuffer) -> MLMultiArray? {
        print("\n🖼️ [CONVERT] Converting CVPixelBuffer to MLMultiArray...")
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        print("🖼️ [CONVERT] Input dimensions: \(width)x\(height)")
        
        guard let multiArray = try? MLMultiArray(shape: [1, 3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32) else {
            print("❌ [CONVERT] Failed to create MLMultiArray")
            return nil
        }
        print("🖼️ [CONVERT] MLMultiArray created with shape: \(multiArray.shape)")
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
            print("🖼️ [CONVERT] CVPixelBuffer unlocked")
        }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("❌ [CONVERT] Failed to get base address")
            return nil
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        print("🖼️ [CONVERT] Bytes per row: \(bytesPerRow)")
        
        var samplePixelValues: [(r: Float, g: Float, b: Float)] = []
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4
                
                let r = Float(buffer[pixelIndex + 1]) / 255.0
                let g = Float(buffer[pixelIndex + 2]) / 255.0
                let b = Float(buffer[pixelIndex + 3]) / 255.0
                
                multiArray[[0, 0, y, x] as [NSNumber]] = NSNumber(value: r)
                multiArray[[0, 1, y, x] as [NSNumber]] = NSNumber(value: g)
                multiArray[[0, 2, y, x] as [NSNumber]] = NSNumber(value: b)
                
                // Collect sample values for debugging
                if samplePixelValues.count < 5 && x % 100 == 0 && y % 100 == 0 {
                    samplePixelValues.append((r: r, g: g, b: b))
                }
            }
        }
        
        print("🖼️ [CONVERT] Sample pixel values: \(samplePixelValues)")
        print("✅ [CONVERT] Conversion completed successfully")
        
        return multiArray
    }
    
    private func imageToPixelBuffer(image: UIImage) -> CVPixelBuffer? {
        print("\n🖼️ [RESIZE] Converting UIImage to CVPixelBuffer...")
        print("🖼️ [RESIZE] Original image size: \(image.size)")
        
        // Resize image to model input size (typically 1024x1024 for SAM)
        let targetSize = modelImageSize
        print("🖼️ [RESIZE] Target size: \(targetSize)")
        
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            print("❌ [RESIZE] Failed to resize image")
            return nil
        }
        UIGraphicsEndImageContext()
        print("✅ [RESIZE] Image resized successfully")
        
        guard let cgImage = resizedImage.cgImage else {
            print("❌ [RESIZE] Failed to get CGImage")
            return nil
        }
        print("🖼️ [RESIZE] CGImage obtained")
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        print("🖼️ [RESIZE] CVPixelBufferCreate status: \(status)")
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            print("❌ [RESIZE] Failed to create CVPixelBuffer, status: \(status)")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: pixelData,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
            print("❌ [RESIZE] Failed to create CGContext")
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        print("✅ [RESIZE] CVPixelBuffer created successfully")
        print("🖼️ [RESIZE] Final buffer dimensions: \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))")
        
        return buffer
    }
    
    private func convertToModelCoordinates(point: CGPoint, imageSize: CGSize, modelSize: CGSize) -> CGPoint {
        print("\n🔄 [COORD] Converting coordinates...")
        print("🔄 [COORD] Original point: \(point)")
        print("🔄 [COORD] Image size: \(imageSize)")
        print("🔄 [COORD] Model size: \(modelSize)")
        
        // Convert from original image coordinates to model coordinates
        let scaleX = modelSize.width / imageSize.width
        let scaleY = modelSize.height / imageSize.height
        
        print("🔄 [COORD] Scale factors - X: \(scaleX), Y: \(scaleY)")
        
        let modelPoint = CGPoint(
            x: point.x * scaleX,
            y: point.y * scaleY
        )
        
        print("🔄 [COORD] Model point: \(modelPoint)")
        print("✅ [COORD] Coordinate conversion completed")
        
        return modelPoint
    }
    
    private func maskToUIImage(mask: MLMultiArray, originalSize: CGSize) -> UIImage? {
        print("\n🎨 [MASK] Converting mask to UIImage...")
        print("🎨 [MASK] Mask shape: \(mask.shape)")
        print("🎨 [MASK] Original size: \(originalSize)")
        
        // Assuming mask is a 2D array with values 0 or 1
        guard mask.shape.count >= 2 else {
            print("❌ [MASK] Invalid mask shape: \(mask.shape)")
            return nil
        }
        
        let height = mask.shape[mask.shape.count - 2].intValue
        let width = mask.shape[mask.shape.count - 1].intValue
        print("🎨 [MASK] Mask dimensions: \(width)x\(height)")
        
        // Create a bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: height * width * bytesPerPixel)
        print("🎨 [MASK] Pixel data array created: \(pixelData.count) bytes")
        
        // Convert mask values to RGBA pixels
        var maskPixelCount = 0
        var transparentPixelCount = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let maskValue = mask[index].floatValue
                let pixelIndex = index * bytesPerPixel
                
                if maskValue > 0.5 { // Mask is present
                    pixelData[pixelIndex] = 255     // R
                    pixelData[pixelIndex + 1] = 0   // G
                    pixelData[pixelIndex + 2] = 0   // B
                    pixelData[pixelIndex + 3] = 128 // A (semi-transparent)
                    maskPixelCount += 1
                } else {
                    pixelData[pixelIndex + 3] = 0   // Transparent
                    transparentPixelCount += 1
                }
            }
        }
        
        print("🎨 [MASK] Mask pixels: \(maskPixelCount)")
        print("🎨 [MASK] Transparent pixels: \(transparentPixelCount)")
        print("🎨 [MASK] Mask coverage: \(Float(maskPixelCount) / Float(maskPixelCount + transparentPixelCount) * 100)%")
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("❌ [MASK] Failed to create CGContext")
            return nil
        }
        
        guard let cgImage = context.makeImage() else {
            print("❌ [MASK] Failed to create CGImage")
            return nil
        }
        
        // Convert back to original image size
        let maskImage = UIImage(cgImage: cgImage)
        print("🎨 [MASK] Intermediate mask image created: \(maskImage.size)")
        
        UIGraphicsBeginImageContextWithOptions(originalSize, false, 1.0)
        maskImage.draw(in: CGRect(origin: .zero, size: originalSize))
        let scaledMask = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        print("✅ [MASK] Final scaled mask created: \(scaledMask?.size ?? .zero)")
        
        return scaledMask
    }
}

enum SAMError: LocalizedError {
    case imageConversionFailed
    case modelPredictionFailed
    
    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to required format"
        case .modelPredictionFailed:
            return "Failed to run model prediction"
        }
    }
}
