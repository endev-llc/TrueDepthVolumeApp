//
//  AutoFlowOverlayView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//

import SwiftUI

// MARK: - Auto-Flow Overlay View
struct AutoFlowOverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let onComplete: () -> Void
    
    @State private var flowState: FlowState = .unifiedSegmentation
    @State private var primaryCroppedCSV: URL?
    @State private var show3DView = false
    
    enum FlowState {
        case unifiedSegmentation
        case backgroundSelection
        case completed
    }
    
    var body: some View {
        ZStack {
            // Original content
            // Unified segmentation phase (combines primary + refinement)
            if flowState == .unifiedSegmentation {
                UnifiedSegmentOverlayView(
                    depthImage: depthImage,
                    photo: photo,
                    cameraManager: cameraManager,
                    onComplete: { croppedCSV in
                        primaryCroppedCSV = croppedCSV
                        flowState = .backgroundSelection
                    },
                    onDismiss: onComplete
                )
                .allowsHitTesting(!cameraManager.isEncodingImages) // Block interactions while encoding
            }
            
            // Background selection phase
            if flowState == .backgroundSelection {
                BackgroundSelectionOverlayView(
                    depthImage: depthImage,
                    photo: photo,
                    cameraManager: cameraManager,
                    onBackgroundComplete: {
                        flowState = .completed
                        show3DView = true
                    },
                    onSkip: {
                        // Clear background points if skipped
                        cameraManager.backgroundSurfacePoints = []
                        flowState = .completed
                        show3DView = true
                    },
                    onDismiss: onComplete
                )
                .allowsHitTesting(!cameraManager.isEncodingImages) // Block interactions while encoding
            }
            
            // Show loading overlay if still encoding
            if cameraManager.isEncodingImages {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Preparing AI models...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .fullScreenCover(isPresented: $show3DView) {
            if let croppedFileURL = cameraManager.croppedFileToShare {
                DepthVisualization3DView(
                    csvFileURL: croppedFileURL,
                    cameraManager: cameraManager,
                    onDismiss: {
                        show3DView = false
                        cameraManager.refinementMask = nil
                        cameraManager.backgroundSurfacePoints = []
                        onComplete()
                    }
                )
            }
        }
    }
}

// MARK: - Unified Segment Overlay View (Primary + Refinement Combined)
struct UnifiedSegmentOverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let onComplete: (URL?) -> Void
    let onDismiss: () -> Void
    
    @State private var photoOpacity: Double = 1.0
    @State private var imageFrame: CGRect = .zero
    
    // USE CAMERA MANAGER'S SAM INSTANCES (already encoded in background)
    @ObservedObject var samManagerDepth: MobileSAMManager
    @ObservedObject var samManagerPhoto: MobileSAMManager
    
    @State private var primaryMaskImage: UIImage?
    @State private var refinementMaskImage: UIImage?
    @State private var primaryMaskHistory: [UIImage] = []
    @State private var refinementMaskHistory: [UIImage] = []
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isDepthEncoded = false
    @State private var isPhotoEncoded = false
    @State private var showConfirmButton = false
    
    // Pen drawing states
    @State private var isPenMode = false
    @State private var brushSize: CGFloat = 30
    @State private var currentDrawingPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var hasPenDrawnMasks = false
    @State private var isDrawingPrimary = true
    
    // Box drawing states
    @State private var boxStartPoint: CGPoint?
    @State private var boxCurrentPoint: CGPoint?
    @State private var isDrawingBox = false
    
    // Add initializer to accept SAM managers from parent
    init(depthImage: UIImage, photo: UIImage?, cameraManager: CameraManager, onComplete: @escaping (URL?) -> Void, onDismiss: @escaping () -> Void) {
        self.depthImage = depthImage
        self.photo = photo
        self.cameraManager = cameraManager
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        self.samManagerDepth = cameraManager.samManagerDepth
        self.samManagerPhoto = cameraManager.samManagerPhoto
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header controls
                HStack(spacing: 20) {
                    Button(action: { onDismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Select Primary & Contents")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Pen mode toggle with color indicator
                    Button(action: {
                        isPenMode.toggle()
                    }) {
                        Image(systemName: isPenMode ? "pencil.circle.fill" : "pencil.circle")
                            .font(.title2)
                            .foregroundColor(isPenMode ? (isDrawingPrimary ? .blue : .yellow) : .white)
                    }
                    
                    // Toggle between primary/refinement pen mode
                    if isPenMode {
                        Button(action: { isDrawingPrimary.toggle() }) {
                            Text(isDrawingPrimary ? "P" : "R")
                                .font(.headline)
                                .foregroundColor(isDrawingPrimary ? .blue : .yellow)
                                .frame(width: 30, height: 30)
                                .background(Circle().stroke(isDrawingPrimary ? Color.blue : Color.yellow, lineWidth: 2))
                        }
                    }
                    
                    // Undo button
                    if !primaryMaskHistory.isEmpty || !refinementMaskHistory.isEmpty {
                        Button(action: { undoLastMask() }) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Clear button
                    if (!primaryMaskHistory.isEmpty || !refinementMaskHistory.isEmpty) && !showConfirmButton {
                        Button(action: { clearAllMasks() }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Confirm button
                    if showConfirmButton {
                        Button(action: { applyMasks() }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal)
                .frame(height: 44)
                
                // Brush size slider (when pen mode is active)
                if isPenMode {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                        Slider(value: $brushSize, in: 10...100)
                            .accentColor(isDrawingPrimary ? .blue : .yellow)
                        Image(systemName: "circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                        Text("\(Int(brushSize))")
                            .foregroundColor(.white)
                            .frame(width: 35)
                    }
                    .padding(.horizontal, 50)
                }
                
                // Opacity slider (only show if photo exists and not in pen mode)
                if photo != nil && !isPenMode {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.white)
                        Slider(value: $photoOpacity, in: 0...1)
                            .accentColor(.blue)
                        Text("\(Int(photoOpacity * 100))%")
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 50)
                }
                
                Spacer()
                
                // Image overlay with proper coordinate space
                GeometryReader { geometry in
                    ZStack {
                        // Depth image (bottom layer)
                        Image(uiImage: depthImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(
                                GeometryReader { imageGeometry in
                                    Color.clear
                                        .onAppear {
                                            updateImageFrame(imageGeometry: imageGeometry)
                                        }
                                        .onChange(of: imageGeometry.size) { _, _ in
                                            updateImageFrame(imageGeometry: imageGeometry)
                                        }
                                }
                            )
                        
                        // Photo (top layer with opacity)
                        if let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // Primary mask overlay (blue tint)
                        if let mask = primaryMaskImage {
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(1.0 - photoOpacity)
                        }

                        // Refinement mask overlay (yellow tint)
                        if let mask = refinementMaskImage {
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // Drawing overlay (for pen mode)
                        if isPenMode && !currentDrawingPath.isEmpty {
                            PenDrawingOverlay(
                                points: $currentDrawingPath,
                                brushSize: brushSize,
                                color: isDrawingPrimary ?
                                    UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 0.7) :
                                    UIColor(red: 255/255, green: 204/255, blue: 0/255, alpha: 0.7),
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Box drawing overlay
                        if boxStartPoint != nil && boxCurrentPoint != nil {
                            BoxDrawingOverlay(
                                startPoint: boxStartPoint!,
                                currentPoint: boxCurrentPoint!,
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Tap indicator
                        if tapLocation != .zero && !isPenMode {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isPenMode && imageFrame.contains(value.location) {
                                    // Pen drawing mode
                                    if !isDrawing {
                                        isDrawing = true
                                        currentDrawingPath = [value.location]
                                    } else {
                                        if let lastPoint = currentDrawingPath.last {
                                            let interpolatedPoints = interpolatePoints(from: lastPoint, to: value.location, spacing: 2.0)
                                            currentDrawingPath.append(contentsOf: interpolatedPoints)
                                        }
                                        currentDrawingPath.append(value.location)
                                    }
                                } else if !isPenMode && imageFrame.contains(value.startLocation) {
                                    // Box drawing mode (auto-detect based on drag distance)
                                    let dragDistance = hypot(value.location.x - value.startLocation.x,
                                                           value.location.y - value.startLocation.y)
                                    
                                    if dragDistance > 10 { // Threshold to distinguish tap from drag
                                        if !isDrawingBox {
                                            isDrawingBox = true
                                            boxStartPoint = value.startLocation
                                            boxCurrentPoint = value.location
                                        } else {
                                            boxCurrentPoint = value.location
                                        }
                                    }
                                }
                            }
                            .onEnded { value in
                                if isPenMode && isDrawing {
                                    finishDrawing()
                                } else if !isPenMode {
                                    let dragDistance = hypot(value.location.x - value.startLocation.x,
                                                           value.location.y - value.startLocation.y)
                                    
                                    if dragDistance > 10 && isDrawingBox {
                                        // It was a box drag
                                        finishBoxDrawing()
                                    } else if dragDistance <= 10 && imageFrame.contains(value.location) {
                                        // It was a tap - do point prompt
                                        handleUnifiedTap(at: value.location)
                                    }
                                }
                            }
                    )
                }
                .coordinateSpace(name: "imageContainer")
                .padding()
                
                Spacer()
                
                // Info text
                Text(getInstructionText())
                    .foregroundColor(.white)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(minHeight: 60, alignment: .top)
                
                // Error message for MobileSAM
                if let errorMessage = samManagerDepth.errorMessage ?? samManagerPhoto.errorMessage {
                    errorMessageView(errorMessage)
                }
            }
        }
        .onAppear {
            startUnifiedSegmentation()
        }
    }
    
    // MARK: - Helper Views
    
    private func errorMessageView(_ message: String) -> some View {
        VStack {
            Spacer()
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text(message)
                    .foregroundColor(.white)
                    .font(.body)
            }
            .padding()
            .background(Color.red.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 1)
            )
            .cornerRadius(8)
            .padding()
        }
    }
    
    // MARK: - Helper Functions
    private func getInstructionText() -> String {
        if isPenMode {
            if isDrawingPrimary {
                return "Draw on primary object (blue). Tap P/R to switch to refinement mode."
            } else {
                return "Draw on food contents (yellow). Tap P/R to switch to primary mode."
            }
        } else if !isDepthEncoded || !isPhotoEncoded {
            return "Encoding images for AI segmentation..."
        } else if primaryMaskImage == nil && refinementMaskImage == nil {
            return "Tap to select or drag to draw box: Blue = primary object, Yellow = food contents inside."
        } else {
            return "Blue = primary, Yellow = contents. Tap or drag box to add more, or tap ✓ when done."
        }
    }
    
    private func updateImageFrame(imageGeometry: GeometryProxy) {
        let frame = imageGeometry.frame(in: .named("imageContainer"))
        imageFrame = frame
        imageDisplaySize = frame.size
    }
    
    private func interpolatePoints(from start: CGPoint, to end: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        
        guard distance > spacing else { return [] }
        
        let steps = Int(distance / spacing)
        var points: [CGPoint] = []
        
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + dx * t
            let y = start.y + dy * t
            points.append(CGPoint(x: x, y: y))
        }
        
        return points
    }
    
    // MARK: - Display Update Function
    private func updateDisplayMasks() {
        // Composite and color primary masks (blue) for display
        if !primaryMaskHistory.isEmpty {
            if let composited = recompositeMaskHistory(primaryMaskHistory) {
                self.primaryMaskImage = colorMask(composited, with: UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0))
            }
        } else {
            self.primaryMaskImage = nil
        }
        
        // Composite and color refinement masks (yellow) for display
        if !refinementMaskHistory.isEmpty {
            if let composited = recompositeMaskHistory(refinementMaskHistory) {
                self.refinementMaskImage = colorMask(composited, with: UIColor(red: 255/255, green: 204/255, blue: 0/255, alpha: 1.0))
            }
        } else {
            self.refinementMaskImage = nil
        }
    }
    
    // MARK: - Unified Segmentation Functions
    private func startUnifiedSegmentation() {
        primaryMaskImage = nil
        refinementMaskImage = nil
        primaryMaskHistory = []
        refinementMaskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        hasPenDrawnMasks = false
        
        // Check if already encoded (from background encoding)
        if samManagerDepth.currentImageEmbeddings != nil && samManagerPhoto.currentImageEmbeddings != nil {
            print("✅ Images already encoded in background - ready immediately!")
            isDepthEncoded = true
            isPhotoEncoded = true
            return
        }
        
        // If not encoded yet, wait or encode now
        print("⏳ Images not yet encoded, encoding now...")
        isDepthEncoded = false
        isPhotoEncoded = false
        
        let photoToSegment = photo ?? depthImage
        
        Task {
            // Only encode if not already done
            async let depthEncodeTask = samManagerDepth.currentImageEmbeddings == nil ?
                samManagerDepth.encodeImage(depthImage) : true
            async let photoEncodeTask = samManagerPhoto.currentImageEmbeddings == nil ?
                samManagerPhoto.encodeImage(photoToSegment) : true
            
            let (depthSuccess, photoSuccess) = await (depthEncodeTask, photoEncodeTask)
            
            await MainActor.run {
                isDepthEncoded = depthSuccess
                isPhotoEncoded = photoSuccess
            }
        }
    }
    
    private func handleUnifiedTap(at location: CGPoint) {
        guard isDepthEncoded && isPhotoEncoded &&
              !samManagerDepth.isLoading && !samManagerPhoto.isLoading &&
              imageFrame.contains(location) else { return }
        
        tapLocation = location
        
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            // Generate masks from both images in parallel
            async let depthMaskTask = samManagerDepth.generateMask(at: relativeLocation, in: imageDisplaySize)
            async let photoMaskTask = samManagerPhoto.generateMask(at: relativeLocation, in: imageDisplaySize)
            
            let (depthMask, photoMask) = await (depthMaskTask, photoMaskTask)
            
            await MainActor.run {
                // Store raw masks from SAM (no coloring yet)
                if let depthMask = depthMask {
                    primaryMaskHistory.append(depthMask)
                }
                
                if let photoMask = photoMask {
                    refinementMaskHistory.append(photoMask)
                }
                
                // Update display versions ONCE
                updateDisplayMasks()
                
                if depthMask != nil || photoMask != nil {
                    self.showConfirmButton = true
                }
            }
        }
    }
    
    // MARK: - Pen Drawing Functions
    private func finishDrawing() {
        guard !currentDrawingPath.isEmpty else {
            isDrawing = false
            return
        }
        
        let targetImage = isDrawingPrimary ? depthImage : (photo ?? depthImage)
        
        // Create mask ONCE in white/grayscale (we'll color it later)
        let whiteColor = UIColor.white
        if let mask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: targetImage.size, color: whiteColor) {
            
            if isDrawingPrimary {
                primaryMaskHistory.append(mask)
            } else {
                refinementMaskHistory.append(mask)
            }
            
            updateDisplayMasks()
            showConfirmButton = true
            hasPenDrawnMasks = true
        }
        
        currentDrawingPath = []
        isDrawing = false
    }
    
    // MARK: - Box Drawing Functions
    private func finishBoxDrawing() {
        guard let start = boxStartPoint, let end = boxCurrentPoint,
              imageFrame.contains(start) && imageFrame.contains(end) else {
            boxStartPoint = nil
            boxCurrentPoint = nil
            isDrawingBox = false
            return
        }
        
        // Create box rect from start and end points
        let minX = min(start.x, end.x) - imageFrame.minX
        let minY = min(start.y, end.y) - imageFrame.minY
        let maxX = max(start.x, end.x) - imageFrame.minX
        let maxY = max(start.y, end.y) - imageFrame.minY
        
        let boxRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        
        Task {
            // Generate masks from both images using box prompt
            async let depthMaskTask = samManagerDepth.generateMask(withBox: boxRect, in: imageDisplaySize)
            async let photoMaskTask = samManagerPhoto.generateMask(withBox: boxRect, in: imageDisplaySize)
            
            let (depthMask, photoMask) = await (depthMaskTask, photoMaskTask)
            
            await MainActor.run {
                // Store raw masks (no coloring yet)
                if let depthMask = depthMask {
                    primaryMaskHistory.append(depthMask)
                }
                
                if let photoMask = photoMask {
                    refinementMaskHistory.append(photoMask)
                }
                
                updateDisplayMasks()
                
                if depthMask != nil || photoMask != nil {
                    self.showConfirmButton = true
                }
                
                boxStartPoint = nil
                boxCurrentPoint = nil
                isDrawingBox = false
            }
        }
    }
    
    private func createMaskFromPath(_ path: [CGPoint], brushSize: CGFloat, in frame: CGRect, imageSize: CGSize, color: UIColor) -> UIImage? {
        let size = imageSize
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        
        let scaledBrushSize = brushSize * (size.width / frame.width)
        context.setLineWidth(scaledBrushSize)
        
        if let firstPoint = path.first {
            let imagePoint = convertToImageCoordinates(firstPoint, frame: frame, imageSize: size)
            context.beginPath()
            context.move(to: imagePoint)
            
            for point in path.dropFirst() {
                let imagePoint = convertToImageCoordinates(point, frame: frame, imageSize: size)
                context.addLine(to: imagePoint)
            }
            
            context.strokePath()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private func convertToImageCoordinates(_ point: CGPoint, frame: CGRect, imageSize: CGSize) -> CGPoint {
        let relativeX = (point.x - frame.minX) / frame.width
        let relativeY = (point.y - frame.minY) / frame.height
        
        return CGPoint(
            x: relativeX * imageSize.width,
            y: relativeY * imageSize.height
        )
    }
    
    private func colorMask(_ mask: UIImage, with color: UIColor) -> UIImage {
        guard let cgImage = mask.cgImage else { return mask }
        
        let width = cgImage.width
        let height = cgImage.height
        
        var maskData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return mask }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        for i in 0..<(width * height) {
            let index = i * 4
            if maskData[index] > 128 {
                maskData[index] = UInt8(r * 255)
                maskData[index + 1] = UInt8(g * 255)
                maskData[index + 2] = UInt8(b * 255)
                maskData[index + 3] = 255
            }
        }
        
        guard let coloredContext = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let coloredCGImage = coloredContext.makeImage() else {
            return mask
        }
        
        return UIImage(cgImage: coloredCGImage, scale: mask.scale, orientation: mask.imageOrientation)
    }
    
    private func recompositeMaskHistory(_ history: [UIImage]) -> UIImage? {
        guard !history.isEmpty else { return nil }
        var result = history[0]
        for i in 1..<history.count {
            result = compositeMasks(result, with: history[i])
        }
        return result
    }
    
    private func undoLastMask() {
        // Prioritize undoing refinement masks first, then primary
        if !refinementMaskHistory.isEmpty {
            refinementMaskHistory.removeLast()
        } else if !primaryMaskHistory.isEmpty {
            primaryMaskHistory.removeLast()
        }
        
        updateDisplayMasks()
        
        if primaryMaskHistory.isEmpty && refinementMaskHistory.isEmpty {
            showConfirmButton = false
            tapLocation = .zero
        }
    }
    
    private func clearAllMasks() {
        primaryMaskHistory = []
        refinementMaskHistory = []
        primaryMaskImage = nil
        refinementMaskImage = nil
        tapLocation = .zero
        showConfirmButton = false
        hasPenDrawnMasks = false
    }
    
    private func applyMasks() {
        // Composite and color brown for processing (done only once here)
        let compositedPrimaryMask: UIImage?
        if !primaryMaskHistory.isEmpty {
            if let composited = recompositeMaskHistory(primaryMaskHistory) {
                compositedPrimaryMask = colorMask(composited, with: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 1.0))
            } else {
                compositedPrimaryMask = nil
            }
        } else {
            compositedPrimaryMask = nil
        }
        
        let compositedRefinementMask: UIImage?
        if !refinementMaskHistory.isEmpty {
            if let composited = recompositeMaskHistory(refinementMaskHistory) {
                compositedRefinementMask = colorMask(composited, with: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 1.0))
            } else {
                compositedRefinementMask = nil
            }
        } else {
            compositedRefinementMask = nil
        }
        
        // STORE REFINEMENT MASK FOR BACKGROUND EXCLUSION:
        cameraManager.refinementMaskForBackground = compositedRefinementMask
        
        print("🔍 Unified Mask Application:")
        print("   Primary mask exists: \(compositedPrimaryMask != nil)")
        print("   Refinement mask exists: \(compositedRefinementMask != nil)")
        
        // First apply primary mask to get cropped CSV
        if let primaryMask = compositedPrimaryMask {
            print("📦 Applying primary mask...")
            cameraManager.cropDepthDataWithMask(primaryMask, imageFrame: imageFrame, depthImageSize: depthImage.size, skipExpansion: hasPenDrawnMasks) {
                // This runs when cropping is actually complete
                if let primaryCSV = self.cameraManager.croppedFileToShare {
                    print("✅ Primary CSV created: \(primaryCSV.lastPathComponent)")
                    
                    // Then apply refinement mask if it exists
                    if let refinementMask = compositedRefinementMask {
                        print("🎯 Applying refinement mask to primary CSV...")
                        self.cameraManager.refineWithSecondaryMask(
                            refinementMask,
                            imageFrame: self.imageFrame,
                            depthImageSize: self.depthImage.size,
                            primaryCroppedCSV: primaryCSV,
                            skipExpansion: self.hasPenDrawnMasks
                        )
                        // refineWithSecondaryMask is synchronous, so we can call completion immediately
                        print("✅ Refinement complete")
                        self.onComplete(self.cameraManager.croppedFileToShare)
                    } else {
                        // No refinement mask, just complete with primary
                        print("ℹ️ No refinement mask - completing with primary only")
                        self.onComplete(self.cameraManager.croppedFileToShare)
                    }
                } else {
                    print("❌ ERROR: Primary CSV not created!")
                    self.onComplete(self.cameraManager.croppedFileToShare)
                }
            }
        } else if let refinementMask = compositedRefinementMask {
            // Only refinement mask exists (unlikely but handle it)
            print("⚠️ Only refinement mask exists - treating as primary")
            cameraManager.cropDepthDataWithMask(refinementMask, imageFrame: imageFrame, depthImageSize: depthImage.size, skipExpansion: hasPenDrawnMasks) {
                self.onComplete(self.cameraManager.croppedFileToShare)
            }
        } else {
            print("❌ ERROR: No masks to apply!")
        }
    }
}

// MARK: - Background Selection Overlay View (UPDATED FOR DUAL-MASK INTERSECTION)
struct BackgroundSelectionOverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let onBackgroundComplete: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void
    
    @State private var imageFrame: CGRect = .zero
    
    // USE CAMERA MANAGER'S SAM INSTANCES (already encoded in background)
    @ObservedObject var samManagerPhoto: MobileSAMManager
    @ObservedObject var samManagerDepth: MobileSAMManager
    
    @State private var maskImage: UIImage?
    @State private var maskHistory: [UIImage] = []
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isPhotoEncoded = false
    @State private var isDepthEncoded = false
    @State private var showConfirmButton = false
    
    // Pen drawing states
    @State private var isPenMode = false
    @State private var brushSize: CGFloat = 30
    @State private var currentDrawingPath: [CGPoint] = []
    @State private var isDrawing = false
    
    // Box drawing states
    @State private var boxStartPoint: CGPoint?
    @State private var boxCurrentPoint: CGPoint?
    @State private var isDrawingBox = false
    
    // Add initializer to accept SAM managers from parent
    init(depthImage: UIImage, photo: UIImage?, cameraManager: CameraManager, onBackgroundComplete: @escaping () -> Void, onSkip: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.depthImage = depthImage
        self.photo = photo
        self.cameraManager = cameraManager
        self.onBackgroundComplete = onBackgroundComplete
        self.onSkip = onSkip
        self.onDismiss = onDismiss
        self.samManagerPhoto = cameraManager.samManagerPhoto
        self.samManagerDepth = cameraManager.samManagerDepth
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header controls
                HStack(spacing: 20) {
                    Button(action: { onDismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Select Background")
                        .foregroundColor(.purple)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Skip button
                    Button(action: { onSkip() }) {
                        Image(systemName: "forward.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    // Pen mode toggle
                    Button(action: {
                        isPenMode.toggle()
                    }) {
                        Image(systemName: isPenMode ? "pencil.circle.fill" : "pencil.circle")
                            .font(.title2)
                            .foregroundColor(isPenMode ? .blue : .white)
                    }
                    
                    // Undo button
                    if !maskHistory.isEmpty {
                        Button(action: { undoLastMask() }) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Clear button
                    if !maskHistory.isEmpty && !showConfirmButton {
                        Button(action: { clearAllMasks() }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Confirm button
                    if showConfirmButton {
                        Button(action: { selectBackgroundSurface() }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal)
                .frame(height: 44)
                
                // Brush size slider (when pen mode is active)
                if isPenMode {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                        Slider(value: $brushSize, in: 10...100)
                            .accentColor(.blue)
                        Image(systemName: "circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                        Text("\(Int(brushSize))")
                            .foregroundColor(.white)
                            .frame(width: 35)
                    }
                    .padding(.horizontal, 50)
                }
                
                Spacer()
                
                // Image overlay with proper coordinate space
                GeometryReader { geometry in
                    ZStack {
                        // Show photo (visual image)
                        if let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay(
                                    GeometryReader { imageGeometry in
                                        Color.clear
                                            .onAppear {
                                                updateImageFrame(imageGeometry: imageGeometry)
                                            }
                                            .onChange(of: imageGeometry.size) { _, _ in
                                                updateImageFrame(imageGeometry: imageGeometry)
                                            }
                                    }
                                )
                        } else {
                            // Fallback to depth image if no photo
                            Image(uiImage: depthImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay(
                                    GeometryReader { imageGeometry in
                                        Color.clear
                                            .onAppear {
                                                updateImageFrame(imageGeometry: imageGeometry)
                                            }
                                            .onChange(of: imageGeometry.size) { _, _ in
                                                updateImageFrame(imageGeometry: imageGeometry)
                                            }
                                    }
                                )
                        }
                        
                        // MobileSAM mask overlay (intersection of photo and depth masks)
                        if let mask = maskImage {
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        
                        if isPenMode && !currentDrawingPath.isEmpty {
                            PenDrawingOverlay(
                                points: $currentDrawingPath,
                                brushSize: brushSize,
                                color: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7),
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Box drawing overlay
                        if boxStartPoint != nil && boxCurrentPoint != nil {
                            BoxDrawingOverlay(
                                startPoint: boxStartPoint!,
                                currentPoint: boxCurrentPoint!,
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Tap indicator
                        if tapLocation != .zero && !isPenMode {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                // REMOVED: .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(height: geo.size.height * 0.05)
                                
                                Spacer()
                                
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(height: geo.size.height * 0.05)
                            }
                            .allowsHitTesting(false)
                        }
                    )
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isPenMode && imageFrame.contains(value.location) {
                                    // Pen drawing mode
                                    if !isDrawing {
                                        isDrawing = true
                                        currentDrawingPath = [value.location]
                                    } else {
                                        if let lastPoint = currentDrawingPath.last {
                                            let interpolatedPoints = interpolatePoints(from: lastPoint, to: value.location, spacing: 2.0)
                                            currentDrawingPath.append(contentsOf: interpolatedPoints)
                                        }
                                        currentDrawingPath.append(value.location)
                                    }
                                } else if !isPenMode && imageFrame.contains(value.startLocation) {
                                    // Box drawing mode (auto-detect based on drag distance)
                                    let dragDistance = hypot(value.location.x - value.startLocation.x,
                                                           value.location.y - value.startLocation.y)
                                    
                                    if dragDistance > 10 { // Threshold to distinguish tap from drag
                                        if !isDrawingBox {
                                            isDrawingBox = true
                                            boxStartPoint = value.startLocation
                                            boxCurrentPoint = value.location
                                        } else {
                                            boxCurrentPoint = value.location
                                        }
                                    }
                                }
                            }
                            .onEnded { value in
                                if isPenMode && isDrawing {
                                    finishDrawing()
                                } else if !isPenMode {
                                    let dragDistance = hypot(value.location.x - value.startLocation.x,
                                                           value.location.y - value.startLocation.y)
                                    
                                    if dragDistance > 10 && isDrawingBox {
                                        // It was a box drag
                                        finishBoxDrawing()
                                    } else if dragDistance <= 10 && imageFrame.contains(value.location) {
                                        // It was a tap - do point prompt
                                        handleBackgroundTap(at: value.location)
                                    }
                                }
                            }
                    )
                }
                .coordinateSpace(name: "backgroundContainer")
                .padding()
                
                Spacer()
                
                // Info text
                Text(getBackgroundInstructionText())
                    .foregroundColor(.white)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(minHeight: 60, alignment: .top)
            }
        }
        .onAppear {
            startBackgroundSegmentation()
        }
    }
    
    // MARK: - Helper Functions
    private func getBackgroundInstructionText() -> String {
        if isPenMode {
            return "Draw on the background surface. Tap ✓ to apply or skip to use automatic plane."
        } else if !isPhotoEncoded || !isDepthEncoded {
            return "Encoding images for precise background selection..."
        } else if maskImage == nil {
            return "Tap the background or drag to draw box. AI will match visual + depth for accuracy."
        } else {
            return "Background mask applied! Tap or drag box to add more, tap ✓ to apply or skip."
        }
    }
    
    private func updateImageFrame(imageGeometry: GeometryProxy) {
        let frame = imageGeometry.frame(in: .named("backgroundContainer"))
        imageFrame = frame
        imageDisplaySize = frame.size
    }
    
    private func interpolatePoints(from start: CGPoint, to end: CGPoint, spacing: CGFloat) -> [CGPoint] {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        
        guard distance > spacing else { return [] }
        
        let steps = Int(distance / spacing)
        var points: [CGPoint] = []
        
        for i in 1..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + dx * t
            let y = start.y + dy * t
            points.append(CGPoint(x: x, y: y))
        }
        
        return points
    }
    
    // UPDATED: Encode both photo AND depth images
    private func startBackgroundSegmentation() {
        maskImage = nil
        maskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        
        // Check if already encoded (from background encoding)
        if samManagerDepth.currentImageEmbeddings != nil && samManagerPhoto.currentImageEmbeddings != nil {
            print("✅ Images already encoded in background - ready immediately!")
            isPhotoEncoded = true
            isDepthEncoded = true
            return
        }
        
        // If not encoded yet, encode now
        print("⏳ Images not yet encoded, encoding now...")
        isPhotoEncoded = false
        isDepthEncoded = false
        
        let photoToSegment = photo ?? depthImage
        
        Task {
            // Only encode if not already done
            async let photoEncodeTask = samManagerPhoto.currentImageEmbeddings == nil ?
                samManagerPhoto.encodeImage(photoToSegment) : true
            async let depthEncodeTask = samManagerDepth.currentImageEmbeddings == nil ?
                samManagerDepth.encodeImage(depthImage) : true
            
            let (photoSuccess, depthSuccess) = await (photoEncodeTask, depthEncodeTask)
            
            await MainActor.run {
                isPhotoEncoded = photoSuccess
                isDepthEncoded = depthSuccess
                
                if photoSuccess && depthSuccess {
                    print("✅ Both photo and depth images encoded for background selection")
                } else {
                    print("⚠️ Encoding status - Photo: \(photoSuccess), Depth: \(depthSuccess)")
                }
            }
        }
    }
    
    // UPDATED: Generate masks with target size optimization
    private func handleBackgroundTap(at location: CGPoint) {
        guard isPhotoEncoded && isDepthEncoded &&
              !samManagerPhoto.isLoading && !samManagerDepth.isLoading &&
              imageFrame.contains(location) else { return }
        
        tapLocation = location
        
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            print("🎯 Generating masks from both visual and depth images...")
            
            // OPTIMIZATION: Generate photo mask at depth image size directly (no resizing needed!)
            let targetSize = depthImage.size
            
            async let photoMaskTask = samManagerPhoto.generateMask(at: relativeLocation, in: imageDisplaySize, outputSize: targetSize)
            async let depthMaskTask = samManagerDepth.generateMask(at: relativeLocation, in: imageDisplaySize)
            
            let (photoMask, depthMask) = await (photoMaskTask, depthMaskTask)
            
            await MainActor.run {
                if let photoMask = photoMask, let depthMask = depthMask {
                    // Intersect the two masks to get only common pixels
                    if let intersectedMask = intersectMasks(photoMask, depthMask, targetSize: targetSize) {
                        print("✅ Successfully intersected photo and depth masks")
                        let filteredMask = filterTopAndBottom5Percent(intersectedMask)
                        // EXCLUDE REFINEMENT MASK PIXELS BEFORE ADDING TO HISTORY:
                        let finalMask = excludeRefinementMaskPixels(filteredMask) ?? filteredMask
                        maskHistory.append(finalMask)
                        self.maskImage = recompositeMaskHistory()
                        self.showConfirmButton = true
                    } else {
                        print("❌ Failed to intersect masks")
                    }
                } else {
                    print("⚠️ One or both masks failed to generate - Photo: \(photoMask != nil), Depth: \(depthMask != nil)")
                    // Fallback to photo mask only if depth mask failed
                    if let photoMask = photoMask {
                        let filteredMask = filterTopAndBottom5Percent(photoMask)
                        // EXCLUDE REFINEMENT MASK PIXELS BEFORE ADDING TO HISTORY:
                        let finalMask = excludeRefinementMaskPixels(filteredMask) ?? filteredMask
                        maskHistory.append(finalMask)
                        self.maskImage = recompositeMaskHistory()
                        self.showConfirmButton = true
                    }
                }
            }
        }
    }

    // UPDATED: Intersect two masks at a target size (now both should already be at target size!)
    private func intersectMasks(_ mask1: UIImage, _ mask2: UIImage, targetSize: CGSize) -> UIImage? {
        // Use the depth image size as target
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        print("🔍 Intersecting masks at target size: \(width)x\(height)")
        print("   Mask1 size: \(mask1.size)")
        print("   Mask2 size: \(mask2.size)")
        
        guard let cgImage1 = mask1.cgImage,
              let cgImage2 = mask2.cgImage else {
            print("❌ Failed to get CGImages from masks")
            return nil
        }
        
        // Extract pixel data from both masks
        var data1 = [UInt8](repeating: 0, count: width * height * 4)
        var data2 = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context1 = CGContext(
            data: &data1,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let context2 = CGContext(
            data: &data2,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("❌ Failed to create contexts")
            return nil
        }
        
        context1.draw(cgImage1, in: CGRect(x: 0, y: 0, width: width, height: height))
        context2.draw(cgImage2, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Create intersected mask data
        var intersectedData = [UInt8](repeating: 0, count: width * height * 4)
        var intersectionCount = 0
        var mask1Count = 0
        var mask2Count = 0
        
        for i in 0..<(width * height) {
            let index = i * 4
            // A pixel is included in the intersection only if it's in both masks (threshold > 128)
            let inMask1 = data1[index] > 128
            let inMask2 = data2[index] > 128
            
            if inMask1 { mask1Count += 1 }
            if inMask2 { mask2Count += 1 }
            
            if inMask1 && inMask2 {
                // Keep the mask color
                intersectedData[index] = 139     // R
                intersectedData[index + 1] = 69  // G
                intersectedData[index + 2] = 19  // B
                intersectedData[index + 3] = 255 // A
                intersectionCount += 1
            }
            // else remains black (0,0,0,0)
        }
        
        print("📊 Mask intersection stats:")
        print("   Photo mask pixels: \(mask1Count)")
        print("   Depth mask pixels: \(mask2Count)")
        print("   Intersected pixels: \(intersectionCount)")
        if mask1Count > 0 && mask2Count > 0 {
            print("   Intersection ratio: \(String(format: "%.1f", Double(intersectionCount) / Double(max(mask1Count, mask2Count)) * 100))%")
        }
        
        // Create CGImage from intersected data
        guard let intersectedContext = CGContext(
            data: &intersectedData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let intersectedCGImage = intersectedContext.makeImage() else {
            print("❌ Failed to create intersected CGImage")
            return nil
        }
        
        return UIImage(cgImage: intersectedCGImage, scale: mask1.scale, orientation: mask1.imageOrientation)
    }

    private func filterTopAndBottom5Percent(_ mask: UIImage) -> UIImage {
        guard let cgImage = mask.cgImage else { return mask }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Extract mask data
        var maskData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var context = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Zero out top 5% and bottom 5% rows
        let topCutoff = Int(Double(height) * 0.05)
        let bottomCutoff = height - topCutoff
        
        for y in 0..<height {
            if y < topCutoff || y >= bottomCutoff {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    maskData[index] = 0
                    maskData[index + 1] = 0
                    maskData[index + 2] = 0
                    maskData[index + 3] = 0
                }
            }
        }
        
        // Create filtered image
        guard let filteredContext = CGContext(
            data: &maskData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let filteredCGImage = filteredContext.makeImage() else {
            return mask
        }
        
        return UIImage(cgImage: filteredCGImage, scale: mask.scale, orientation: mask.imageOrientation)
    }
    
    // MARK: - Refinement Mask Exclusion
    private func excludeRefinementMaskPixels(_ backgroundMask: UIImage) -> UIImage? {
        guard let refinementMask = cameraManager.refinementMaskForBackground,
              let bgCGImage = backgroundMask.cgImage,
              let refinementCGImage = refinementMask.cgImage else {
            return backgroundMask
        }
        
        let width = bgCGImage.width
        let height = bgCGImage.height
        
        // Resize refinement mask to match background mask dimensions if needed
        let resizedRefinementMask: UIImage
        if refinementCGImage.width != width || refinementCGImage.height != height {
            resizedRefinementMask = resizeMaskEfficiently(refinementMask, to: CGSize(width: width, height: height)) ?? refinementMask
        } else {
            resizedRefinementMask = refinementMask
        }
        
        guard let resizedRefinementCGImage = resizedRefinementMask.cgImage else {
            return backgroundMask
        }
        
        // Extract pixel data
        var bgData = [UInt8](repeating: 0, count: width * height * 4)
        var refinementData = [UInt8](repeating: 0, count: width * height * 4)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let bgContext = CGContext(
            data: &bgData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let refinementContext = CGContext(
            data: &refinementData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return backgroundMask
        }
        
        bgContext.draw(bgCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        refinementContext.draw(resizedRefinementCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Create result mask - exclude pixels that are in refinement mask
        var resultData = [UInt8](repeating: 0, count: width * height * 4)
        var excludedCount = 0
        
        for i in 0..<(width * height) {
            let index = i * 4
            let bgMasked = bgData[index] > 128
            let refinementMasked = refinementData[index] > 128
            
            // Only include if in background mask AND NOT in refinement mask
            if bgMasked && !refinementMasked {
                resultData[index] = 139     // R
                resultData[index + 1] = 69  // G
                resultData[index + 2] = 19  // B
                resultData[index + 3] = 255 // A
            } else if bgMasked && refinementMasked {
                excludedCount += 1
            }
        }
        
        print("🚫 Excluded \(excludedCount) background pixels that overlap with refinement mask")
        
        // Create result image
        guard let resultContext = CGContext(
            data: &resultData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let resultCGImage = resultContext.makeImage() else {
            return backgroundMask
        }
        
        return UIImage(cgImage: resultCGImage, scale: backgroundMask.scale, orientation: backgroundMask.imageOrientation)
    }
    
    // NEW: Efficiently resize a mask image using CoreGraphics
    private func resizeMaskEfficiently(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Use high quality interpolation for masks
        context.interpolationQuality = .high
        
        // Draw the image scaled to the target size
        if let cgImage = image.cgImage {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        guard let scaledCGImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: scaledCGImage, scale: 1.0, orientation: image.imageOrientation)
    }
    
    // MARK: - Pen Drawing Functions
    private func finishDrawing() {
        guard !currentDrawingPath.isEmpty else {
            isDrawing = false
            return
        }
        
        let imageToUse = photo ?? depthImage
        
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: imageToUse.size) {
            // EXCLUDE REFINEMENT MASK PIXELS BEFORE ADDING TO HISTORY:
            let finalMask = excludeRefinementMaskPixels(drawnMask) ?? drawnMask
            maskHistory.append(finalMask)
            maskImage = recompositeMaskHistory()
            showConfirmButton = true
        }
        
        currentDrawingPath = []
        isDrawing = false
    }
    
    // MARK: - Box Drawing Functions
    // UPDATED: Generate masks with target size optimization
    private func finishBoxDrawing() {
        guard let start = boxStartPoint, let end = boxCurrentPoint,
              imageFrame.contains(start) && imageFrame.contains(end) else {
            boxStartPoint = nil
            boxCurrentPoint = nil
            isDrawingBox = false
            return
        }
        
        // Create box rect from start and end points
        let minX = min(start.x, end.x) - imageFrame.minX
        let minY = min(start.y, end.y) - imageFrame.minY
        let maxX = max(start.x, end.x) - imageFrame.minX
        let maxY = max(start.y, end.y) - imageFrame.minY
        
        let boxRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        
        Task {
            print("🎯 Generating background masks from box prompt...")
            
            // OPTIMIZATION: Generate photo mask at depth image size directly (no resizing needed!)
            let targetSize = depthImage.size
            
            async let photoMaskTask = samManagerPhoto.generateMask(withBox: boxRect, in: imageDisplaySize, outputSize: targetSize)
            async let depthMaskTask = samManagerDepth.generateMask(withBox: boxRect, in: imageDisplaySize)
            
            let (photoMask, depthMask) = await (photoMaskTask, depthMaskTask)
            
            await MainActor.run {
                if let photoMask = photoMask, let depthMask = depthMask {
                    // Intersect the two masks
                    if let intersectedMask = intersectMasks(photoMask, depthMask, targetSize: targetSize) {
                        print("✅ Successfully intersected photo and depth masks from box")
                        let filteredMask = filterTopAndBottom5Percent(intersectedMask)
                        // EXCLUDE REFINEMENT MASK PIXELS BEFORE ADDING TO HISTORY:
                        let finalMask = excludeRefinementMaskPixels(filteredMask) ?? filteredMask
                        maskHistory.append(finalMask)
                        self.maskImage = recompositeMaskHistory()
                        self.showConfirmButton = true
                    } else {
                        print("❌ Failed to intersect masks from box")
                    }
                } else {
                    print("⚠️ One or both masks failed to generate from box - Photo: \(photoMask != nil), Depth: \(depthMask != nil)")
                    // Fallback to photo mask only if depth mask failed
                    if let photoMask = photoMask {
                        let filteredMask = filterTopAndBottom5Percent(photoMask)
                        // EXCLUDE REFINEMENT MASK PIXELS BEFORE ADDING TO HISTORY:
                        let finalMask = excludeRefinementMaskPixels(filteredMask) ?? filteredMask
                        maskHistory.append(finalMask)
                        self.maskImage = recompositeMaskHistory()
                        self.showConfirmButton = true
                    }
                }
                
                boxStartPoint = nil
                boxCurrentPoint = nil
                isDrawingBox = false
            }
        }
    }
    
    private func createMaskFromPath(_ path: [CGPoint], brushSize: CGFloat, in frame: CGRect, imageSize: CGSize) -> UIImage? {
        let size = imageSize
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 1.0).cgColor)
        
        let scaledBrushSize = brushSize * (size.width / frame.width)
        context.setLineWidth(scaledBrushSize)
        
        if let firstPoint = path.first {
            let imagePoint = convertToImageCoordinates(firstPoint, frame: frame, imageSize: size)
            context.beginPath()
            context.move(to: imagePoint)
            
            for point in path.dropFirst() {
                let imagePoint = convertToImageCoordinates(point, frame: frame, imageSize: size)
                context.addLine(to: imagePoint)
            }
            
            context.strokePath()
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private func convertToImageCoordinates(_ point: CGPoint, frame: CGRect, imageSize: CGSize) -> CGPoint {
        let relativeX = (point.x - frame.minX) / frame.width
        let relativeY = (point.y - frame.minY) / frame.height
        
        return CGPoint(
            x: relativeX * imageSize.width,
            y: relativeY * imageSize.height
        )
    }
    
    private func recompositeMaskHistory() -> UIImage? {
        guard !maskHistory.isEmpty else { return nil }
        var result = maskHistory[0]
        for i in 1..<maskHistory.count {
            result = compositeMasks(result, with: maskHistory[i])
        }
        return result
    }
    
    private func undoLastMask() {
        guard !maskHistory.isEmpty else { return }
        maskHistory.removeLast()
        maskImage = recompositeMaskHistory()
        if maskHistory.isEmpty {
            showConfirmButton = false
            tapLocation = .zero
        }
    }
    
    private func clearAllMasks() {
        maskHistory = []
        maskImage = nil
        tapLocation = .zero
        showConfirmButton = false
    }
    
    private func selectBackgroundSurface() {
        guard let maskImage = maskImage else { return }
        
        // Extract background surface points from depth data using the intersected mask
        cameraManager.extractBackgroundSurfacePoints(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onBackgroundComplete()
        }
    }
}

// MARK: - Pen Drawing Overlay
struct PenDrawingOverlay: UIViewRepresentable {
    @Binding var points: [CGPoint]
    let brushSize: CGFloat
    let color: UIColor
    let imageFrame: CGRect
    
    func makeUIView(context: Context) -> PenDrawingCanvasView {
        let view = PenDrawingCanvasView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: PenDrawingCanvasView, context: Context) {
        uiView.points = points
        uiView.brushSize = brushSize
        uiView.color = color
        uiView.imageFrame = imageFrame
        uiView.setNeedsDisplay()
    }
}

class PenDrawingCanvasView: UIView {
    var points: [CGPoint] = []
    var brushSize: CGFloat = 30
    var color: UIColor = UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7)
    var imageFrame: CGRect = .zero
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !points.isEmpty else { return }
        
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(brushSize)
        
        if let firstPoint = points.first {
            context.beginPath()
            context.move(to: firstPoint)
            
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            
            context.strokePath()
        }
    }
}

// MARK: - Box Drawing Overlay
struct BoxDrawingOverlay: View {
    let startPoint: CGPoint
    let currentPoint: CGPoint
    let imageFrame: CGRect
    
    var body: some View {
        let minX = min(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let maxX = max(startPoint.x, currentPoint.x)
        let maxY = max(startPoint.y, currentPoint.y)
        
        Rectangle()
            .stroke(Color.green, lineWidth: 3)
            .frame(width: maxX - minX, height: maxY - minY)
            .position(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
}
