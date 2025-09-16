import Foundation
import UIKit
import OnnxRuntimeBindings
import CoreML
import Accelerate

class MobileSAMManager: ObservableObject {
    private var encoderSession: ORTSession?
    private var decoderSession: ORTSession?
    private var environment: ORTEnv?
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentImageEmbeddings: ORTValue?
    @Published var originalImageSize: CGSize = .zero
    
    // Store exact preprocessing parameters used for encoder
    private let modelInputSize: CGFloat = 1024
    private var preScale: CGFloat = 1.0         // how you resized the image
    private var prePadX: CGFloat = 0.0          // horizontal padding applied before encoding
    private var prePadY: CGFloat = 0.0          // vertical padding applied before encoding
    
    init() {
        setupONNXRuntime()
    }
    
    private func setupONNXRuntime() {
        do {
            environment = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            
            // Load encoder model
            guard let encoderPath = Bundle.main.path(forResource: "mobile_sam_encoder", ofType: "onnx") else {
                errorMessage = "Encoder model file not found"
                return
            }
            
            // Load decoder model
            guard let decoderPath = Bundle.main.path(forResource: "mobile_sam", ofType: "onnx") else {
                errorMessage = "Decoder model file not found"
                return
            }
            
            encoderSession = try ORTSession(env: environment!, modelPath: encoderPath, sessionOptions: options)
            decoderSession = try ORTSession(env: environment!, modelPath: decoderPath, sessionOptions: options)
            
        } catch {
            errorMessage = "Failed to initialize ONNX Runtime: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Image Encoding
    func encodeImage(_ image: UIImage) async -> Bool {
        guard let encoderSession = encoderSession else {
            await MainActor.run {
                errorMessage = "Encoder session not initialized"
            }
            return false
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            originalImageSize = image.size
        }
        
        do {
            // Preprocess image
            let preprocessedImage = preprocessImage(image)
            
            // Convert to tensor
            let inputTensor = try createImageTensor(from: preprocessedImage)
            
            // Run inference
            let outputs = try encoderSession.run(withInputs: ["images": inputTensor], outputNames: ["image_embeddings"], runOptions: nil)
            
            await MainActor.run {
                currentImageEmbeddings = outputs["image_embeddings"]
                isLoading = false
            }
            
            return true
            
        } catch {
            await MainActor.run {
                errorMessage = "Encoding failed: \(error.localizedDescription)"
                isLoading = false
            }
            return false
        }
    }
    
    // MARK: - Mask Generation
    func generateMask(at point: CGPoint, in imageDisplaySize: CGSize) async -> UIImage? {
        guard let decoderSession = decoderSession,
              let imageEmbeddings = currentImageEmbeddings else {
            await MainActor.run {
                errorMessage = "Models not ready or image not encoded"
            }
            return nil
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            // Convert UI coordinates to model coordinates
            let modelCoords = convertUICoordinateToModelCoordinate(point, displaySize: imageDisplaySize)
            
            // Create prompt tensors
            let pointCoords = try createPointCoordsTensor(x: modelCoords.x, y: modelCoords.y)
            let pointLabels = try createPointLabelsTensor()
            let maskInput = try createMaskInputTensor()
            let hasMaskInput = try createHasMaskInputTensor()
            let origImSize = try createOrigImageSizeTensor()
            
            // Prepare inputs
            let inputs: [String: ORTValue] = [
                "image_embeddings": imageEmbeddings,
                "point_coords": pointCoords,
                "point_labels": pointLabels,
                "mask_input": maskInput,
                "has_mask_input": hasMaskInput,
                "orig_im_size": origImSize
            ]
            
            // Run inference
            let outputs = try decoderSession.run(withInputs: inputs, outputNames: ["masks", "iou_predictions", "low_res_masks"], runOptions: nil)
            
            await MainActor.run {
                isLoading = false
            }
            
            // Convert mask to UIImage
            if let masks = outputs["masks"] {
                return try createMaskImage(from: masks)
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Mask generation failed: \(error.localizedDescription)"
                isLoading = false
            }
        }
        
        return nil
    }
    
    // MARK: - Image Preprocessing
    private func preprocessImage(_ image: UIImage) -> UIImage {
        // Mobile SAM expects 1024x1024 - draw resized image at origin (0,0)
        let targetSize = CGSize(width: 1024, height: 1024)
        let imageSize = image.size
        
        // Calculate scale to fit image within 1024x1024 while preserving aspect ratio
        let scale = min(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        // Store the exact preprocessing parameters
        preScale = scale
        prePadX = 0.0  // Drawing at origin (top-left)
        prePadY = 0.0  // Drawing at origin (top-left)
        
        print("ENCODER PREPROCESS — scale=\(preScale), padX=\(prePadX), padY=\(prePadY), scaled=\(scaledSize.width)x\(scaledSize.height)")
        
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        
        // Fill with zeros (black background)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: targetSize))
        
        // Draw image at origin (top-left) with preserved aspect ratio
        let drawRect = CGRect(x: 0, y: 0, width: scaledSize.width, height: scaledSize.height)
        image.draw(in: drawRect)
        
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage ?? image
    }
    
    private func createImageTensor(from image: UIImage) throws -> ORTValue {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "ImageProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage"])
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create pixel data
        var pixelData = [Float32]()
        pixelData.reserveCapacity(width * height * 3)
        
        // Extract RGB values and normalize
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: height * width * bytesPerPixel)
        let context = CGContext(data: &rawData,
                               width: width,
                               height: height,
                               bitsPerComponent: bitsPerComponent,
                               bytesPerRow: bytesPerRow,
                               space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Convert to normalized float values [0, 1] and arrange as CHW format
        let mean: [Float32] = [0.485, 0.456, 0.406]  // ImageNet mean
        let std: [Float32] = [0.229, 0.224, 0.225]   // ImageNet std
        
        // R channel
        for i in 0..<(height * width) {
            let pixelIndex = i * bytesPerPixel
            let r = Float32(rawData[pixelIndex]) / 255.0
            let normalizedR = (r - mean[0]) / std[0]
            pixelData.append(normalizedR)
        }
        
        // G channel
        for i in 0..<(height * width) {
            let pixelIndex = i * bytesPerPixel + 1
            let g = Float32(rawData[pixelIndex]) / 255.0
            let normalizedG = (g - mean[1]) / std[1]
            pixelData.append(normalizedG)
        }
        
        // B channel
        for i in 0..<(height * width) {
            let pixelIndex = i * bytesPerPixel + 2
            let b = Float32(rawData[pixelIndex]) / 255.0
            let normalizedB = (b - mean[2]) / std[2]
            pixelData.append(normalizedB)
        }
        
        // Create tensor shape [1, 3, 1024, 1024]
        let shape: [NSNumber] = [1, 3, NSNumber(value: height), NSNumber(value: width)]
        let tensorData = NSMutableData(bytes: &pixelData, length: pixelData.count * MemoryLayout<Float32>.size)
        
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    // MARK: - Coordinate Conversion
    private func convertUICoordinateToModelCoordinate(_ point: CGPoint, displaySize: CGSize) -> CGPoint {
        // normalize in the displayed image's frame
        let nx = point.x / displaySize.width
        let ny = point.y / displaySize.height

        // size of the image after encoder's resize
        let scaledW = originalImageSize.width  * preScale
        let scaledH = originalImageSize.height * preScale

        // map into the encoder's 1024×1024 canvas using the SAME padding you used at encode time
        let modelX = prePadX + nx * scaledW
        let modelY = prePadY + ny * scaledH

        print("POINT MAP — nx=\(nx), ny=\(ny) → model(\(Int(modelX)), \(Int(modelY)))  scale=\(preScale) pad=(\(prePadX),\(prePadY))")
        return CGPoint(x: modelX, y: modelY)
    }
    
    // MARK: - Tensor Creation for Decoder
    private func createPointCoordsTensor(x: CGFloat, y: CGFloat) throws -> ORTValue {
        var coords: [Float32] = [Float32(x), Float32(y)]
        let shape: [NSNumber] = [1, 1, 2]  // [batch, num_points, 2]
        let tensorData = NSMutableData(bytes: &coords, length: coords.count * MemoryLayout<Float32>.size)
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    private func createPointLabelsTensor() throws -> ORTValue {
        var labels: [Float32] = [1.0]  // 1 for foreground point
        let shape: [NSNumber] = [1, 1]  // [batch, num_points]
        let tensorData = NSMutableData(bytes: &labels, length: labels.count * MemoryLayout<Float32>.size)
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    private func createMaskInputTensor() throws -> ORTValue {
        let size = 1 * 1 * 256 * 256
        var maskInput = [Float32](repeating: 0.0, count: size)
        let shape: [NSNumber] = [1, 1, 256, 256]
        let tensorData = NSMutableData(bytes: &maskInput, length: maskInput.count * MemoryLayout<Float32>.size)
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    private func createHasMaskInputTensor() throws -> ORTValue {
        var hasMask: [Float32] = [0.0]  // No previous mask
        let shape: [NSNumber] = [1]
        let tensorData = NSMutableData(bytes: &hasMask, length: hasMask.count * MemoryLayout<Float32>.size)
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    private func createOrigImageSizeTensor() throws -> ORTValue {
        var size: [Float32] = [Float32(originalImageSize.height), Float32(originalImageSize.width)]
        let shape: [NSNumber] = [2]
        let tensorData = NSMutableData(bytes: &size, length: size.count * MemoryLayout<Float32>.size)
        return try ORTValue(tensorData: tensorData, elementType: .float, shape: shape)
    }
    
    // MARK: - Mask Image Creation
    private func createMaskImage(from maskTensor: ORTValue) throws -> UIImage? {
        guard let tensorData = try maskTensor.tensorData() as Data? else {
            throw NSError(domain: "MaskProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get tensor data"])
        }
        
        let shape = try maskTensor.tensorTypeAndShapeInfo().shape
        guard shape.count >= 4 else {
            throw NSError(domain: "MaskProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid mask shape"])
        }
        
        let batchSize = shape[0].intValue
        let numMasks = shape[1].intValue
        let height = shape[2].intValue      // This should be 2208
        let width = shape[3].intValue       // This should be 1242
        
        print("Mask tensor shape: \(shape)")
        print("Interpreted as: batch=\(batchSize), masks=\(numMasks), height=\(height), width=\(width)")
        print("Original image size: \(originalImageSize)")
        
        // Verify dimensions match original image
        let expectedWidth = Int(originalImageSize.width)   // 1242
        let expectedHeight = Int(originalImageSize.height) // 2208
        
        print("Expected: \(expectedWidth)x\(expectedHeight), Got: \(width)x\(height)")
        
        // Extract float data
        let floatCount = tensorData.count / MemoryLayout<Float32>.size
        var floatArray = [Float32](repeating: 0, count: floatCount)
        
        tensorData.withUnsafeBytes { bytes in
            let floatBuffer = bytes.bindMemory(to: Float32.self)
            for i in 0..<min(floatCount, floatBuffer.count) {
                floatArray[i] = floatBuffer[i]
            }
        }
        
        // Create binary mask - use the best mask (usually index 0)
        var pixelData = [UInt8]()
        pixelData.reserveCapacity(width * height * 4)
        
        let maskStartIndex = 0 * width * height // First mask
        
        for y in 0..<height {
            for x in 0..<width {
                let index = maskStartIndex + y * width + x
                let maskValue: UInt8 = index < floatArray.count && floatArray[index] > 0.0 ? 255 : 0
                
                pixelData.append(maskValue)  // R
                pixelData.append(UInt8(0))   // G
                pixelData.append(UInt8(0))   // B
                pixelData.append(maskValue)  // A
            }
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(data: &pixelData,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: 4 * width,
                                     space: colorSpace,
                                     bitmapInfo: bitmapInfo.rawValue),
              let cgImage = context.makeImage() else {
            print("Failed to create CGImage")
            return nil
        }
        
        let maskImage = UIImage(cgImage: cgImage)
        print("Created mask image with size: \(maskImage.size)")
        
        return maskImage
    }
}
