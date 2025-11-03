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
    
    @State private var flowState: FlowState = .primarySegmentation
    @State private var primaryCroppedCSV: URL?
    @State private var show3DView = false
    
    enum FlowState {
        case primarySegmentation
        case refinement
        case backgroundSelection
        case completed
    }
    
    var body: some View {
        ZStack {
            // Primary segmentation phase
            if flowState == .primarySegmentation {
                AutoSegmentOverlayView(
                    depthImage: depthImage,
                    photo: photo,
                    cameraManager: cameraManager,
                    onPrimaryComplete: { croppedCSV in
                        primaryCroppedCSV = croppedCSV
                        flowState = .refinement
                    },
                    onDismiss: onComplete
                )
            }
            
            // Refinement phase
            if flowState == .refinement {
                RefinementOverlayView(
                    depthImage: cameraManager.croppedPhoto ?? depthImage,
                    photo: cameraManager.croppedPhoto,
                    cameraManager: cameraManager,
                    primaryCroppedCSV: primaryCroppedCSV,
                    onRefinementComplete: {
                        flowState = .backgroundSelection
                    },
                    onSkip: {
                        flowState = .backgroundSelection
                    },
                    onDismiss: onComplete
                )
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

// MARK: - Auto-Segment Overlay View (Primary Phase)
struct AutoSegmentOverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let onPrimaryComplete: (URL?) -> Void
    let onDismiss: () -> Void
    
    @State private var photoOpacity: Double = 0.7
    @State private var showingDepthOnly = false
    @State private var imageFrame: CGRect = .zero
    
    // MobileSAM integration
    @StateObject private var samManager = MobileSAMManager()
    @State private var maskImage: UIImage?
    @State private var maskHistory: [UIImage] = []
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    @State private var showConfirmButton = false
    
    // Pen drawing states
    @State private var isPenMode = false
    @State private var brushSize: CGFloat = 30
    @State private var currentDrawingPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var hasPenDrawnMasks = false
    
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
                    
                    Text("Select Primary")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Pen mode toggle
                    Button(action: { isPenMode.toggle() }) {
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
                        Button(action: { cropCSVWithMask() }) {
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
                
                // Opacity slider (only show if photo exists and not depth only and not in pen mode)
                if !showingDepthOnly && photo != nil && !isPenMode {
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
                        if !showingDepthOnly, let photo = photo {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(photoOpacity)
                        }
                        
                        // MobileSAM mask overlay
                        if let mask = maskImage {
                            Image(uiImage: mask)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        
                        // Drawing overlay (for pen mode)
                        if isPenMode && !currentDrawingPath.isEmpty {
                            PenDrawingOverlay(
                                points: $currentDrawingPath,
                                brushSize: brushSize,
                                color: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7),
                                imageFrame: imageFrame
                            )
                        }
                        
                        // Tap indicator for auto-segmentation
                        if tapLocation != .zero && !isPenMode {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isPenMode && imageFrame.contains(value.location) {
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
                                }
                            }
                            .onEnded { _ in
                                if isPenMode && isDrawing {
                                    finishDrawing()
                                }
                            }
                    )
                    .onTapGesture { location in
                        if !isPenMode {
                            handleAutoSegmentTap(at: location)
                        }
                    }
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
                if let errorMessage = samManager.errorMessage {
                    errorMessageView(errorMessage)
                }
            }
        }
        .onAppear {
            startAutoSegmentation()
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
            return "Draw on the primary object with your finger. Tap ✓ when done."
        } else if !isImageEncoded {
            return "Encoding image for AI segmentation..."
        } else if maskImage == nil {
            return "Tap anywhere on the primary object you want to measure."
        } else {
            return "AI mask applied! Tap more areas to add to mask, or tap ✓ when done."
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
    
    // MARK: - Auto-Segmentation Functions
    private func startAutoSegmentation() {
        maskImage = nil
        maskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        hasPenDrawnMasks = false
        
        Task {
            let success = await samManager.encodeImage(depthImage)
            await MainActor.run {
                isImageEncoded = success
            }
        }
    }
    
    private func handleAutoSegmentTap(at location: CGPoint) {
        guard isImageEncoded && !samManager.isLoading && imageFrame.contains(location) else { return }
        
        tapLocation = location
        
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    maskHistory.append(mask)
                    self.maskImage = recompositeMaskHistory()
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
        
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: depthImage.size) {
            maskHistory.append(drawnMask)
            maskImage = recompositeMaskHistory()
            showConfirmButton = true
            hasPenDrawnMasks = true
        }
        
        currentDrawingPath = []
        isDrawing = false
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
        hasPenDrawnMasks = false
    }
    
    private func cropCSVWithMask() {
        guard let maskImage = maskImage else { return }
        
        cameraManager.cropDepthDataWithMask(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size, skipExpansion: hasPenDrawnMasks)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onPrimaryComplete(cameraManager.croppedFileToShare)
        }
    }
}

// MARK: - Refinement Overlay View (Secondary Phase)
struct RefinementOverlayView: View {
    let depthImage: UIImage
    let photo: UIImage?
    let cameraManager: CameraManager
    let primaryCroppedCSV: URL?
    let onRefinementComplete: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void
    
    @State private var imageFrame: CGRect = .zero
    
    // MobileSAM integration
    @StateObject private var samManager = MobileSAMManager()
    @State private var maskImage: UIImage?
    @State private var maskHistory: [UIImage] = []
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    @State private var showConfirmButton = false
    
    // Pen drawing states
    @State private var isPenMode = false
    @State private var brushSize: CGFloat = 30
    @State private var currentDrawingPath: [CGPoint] = []
    @State private var isDrawing = false
    @State private var hasPenDrawnMasks = false
    
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
                    
                    Text("Refine Contents")
                        .foregroundColor(.yellow)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Skip button
                    Button(action: { onSkip() }) {
                        Image(systemName: "forward.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    // Pen mode toggle
                    Button(action: { isPenMode.toggle() }) {
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
                        Button(action: { applyRefinementMask() }) {
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
                        // Cropped image
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
                        
                        // MobileSAM mask overlay
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
                        
                        // Tap indicator
                        if tapLocation != .zero && !isPenMode {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isPenMode && imageFrame.contains(value.location) {
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
                                }
                            }
                            .onEnded { _ in
                                if isPenMode && isDrawing {
                                    finishDrawing()
                                }
                            }
                    )
                    .onTapGesture { location in
                        if !isPenMode {
                            handleRefinementTap(at: location)
                        }
                    }
                }
                .coordinateSpace(name: "refinementContainer")
                .padding()
                
                Spacer()
                
                // Info text
                Text(getRefinementInstructionText())
                    .foregroundColor(.white)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(minHeight: 60, alignment: .top)
            }
        }
        .onAppear {
            startRefinementSegmentation()
        }
    }
    
    // MARK: - Helper Functions
    private func getRefinementInstructionText() -> String {
        if isPenMode {
            return "Draw on the food contents to isolate. Tap ✓ to apply or skip to use full object."
        } else if !isImageEncoded {
            return "Encoding image for refinement..."
        } else if maskImage == nil {
            return "Tap the food contents you want to isolate, or skip to use the full primary object."
        } else {
            return "Mask applied! Tap more areas to add, tap ✓ to apply or skip to use full object."
        }
    }
    
    private func updateImageFrame(imageGeometry: GeometryProxy) {
        let frame = imageGeometry.frame(in: .named("refinementContainer"))
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
    
    private func startRefinementSegmentation() {
        maskImage = nil
        maskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        hasPenDrawnMasks = false
        
        let imageToSegment = photo ?? depthImage
        
        Task {
            let success = await samManager.encodeImage(imageToSegment)
            await MainActor.run {
                isImageEncoded = success
            }
        }
    }
    
    private func handleRefinementTap(at location: CGPoint) {
        guard isImageEncoded && !samManager.isLoading && imageFrame.contains(location) else { return }
        
        tapLocation = location
        
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    maskHistory.append(mask)
                    self.maskImage = recompositeMaskHistory()
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
        
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: depthImage.size) {
            maskHistory.append(drawnMask)
            maskImage = recompositeMaskHistory()
            showConfirmButton = true
            hasPenDrawnMasks = true
        }
        
        currentDrawingPath = []
        isDrawing = false
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
        hasPenDrawnMasks = false
    }
    
    private func applyRefinementMask() {
        guard let maskImage = maskImage,
              let primaryCSV = primaryCroppedCSV else { return }
        
        cameraManager.refineWithSecondaryMask(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size, primaryCroppedCSV: primaryCSV, skipExpansion: hasPenDrawnMasks)
        
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            onRefinementComplete()
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
    
    // Dual MobileSAM integration - one for photo, one for depth
    @StateObject private var samManagerPhoto = MobileSAMManager()
    @StateObject private var samManagerDepth = MobileSAMManager()
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
                    Button(action: { isPenMode.toggle() }) {
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
                        
                        // Tap indicator
                        if tapLocation != .zero && !isPenMode {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
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
                                }
                            }
                            .onEnded { _ in
                                if isPenMode && isDrawing {
                                    finishDrawing()
                                }
                            }
                    )
                    .onTapGesture { location in
                        if !isPenMode {
                            handleBackgroundTap(at: location)
                        }
                    }
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
            return "Tap the background surface. AI will match visual + depth for accuracy."
        } else {
            return "Background mask applied! Tap more areas to add, tap ✓ to apply or skip."
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
        isPhotoEncoded = false
        isDepthEncoded = false
        
        let photoToSegment = photo ?? depthImage
        
        Task {
            // Encode both images in parallel
            async let photoEncodeTask = samManagerPhoto.encodeImage(photoToSegment)
            async let depthEncodeTask = samManagerDepth.encodeImage(depthImage)
            
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
    
    // UPDATED: Generate masks from BOTH images and intersect them
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
            
            // Generate masks from both images in parallel
            async let photoMaskTask = samManagerPhoto.generateMask(at: relativeLocation, in: imageDisplaySize)
            async let depthMaskTask = samManagerDepth.generateMask(at: relativeLocation, in: imageDisplaySize)
            
            let (photoMask, depthMask) = await (photoMaskTask, depthMaskTask)
            
            await MainActor.run {
                if let photoMask = photoMask, let depthMask = depthMask {
                    // Intersect the two masks to get only common pixels
                    // Use depth image dimensions (smaller) to avoid memory issues
                    let targetSize = depthImage.size
                    
                    if let intersectedMask = intersectMasks(photoMask, depthMask, targetSize: targetSize) {
                        print("✅ Successfully intersected photo and depth masks")
                        let filteredMask = filterTopAndBottom5Percent(intersectedMask)
                        maskHistory.append(filteredMask)
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
                        maskHistory.append(filteredMask)
                        self.maskImage = recompositeMaskHistory()
                        self.showConfirmButton = true
                    }
                }
            }
        }
    }

    // UPDATED: Intersect two masks at a target size to avoid memory issues
    private func intersectMasks(_ mask1: UIImage, _ mask2: UIImage, targetSize: CGSize) -> UIImage? {
        // Use the depth image size as target (smaller dimension to avoid memory issues)
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        print("📏 Intersecting masks at target size: \(width)x\(height)")
        print("   Original mask1 size: \(mask1.size)")
        print("   Original mask2 size: \(mask2.size)")
        
        // Resize both masks to target size efficiently
        guard let resizedMask1 = resizeMaskEfficiently(mask1, to: CGSize(width: width, height: height)),
              let resizedMask2 = resizeMaskEfficiently(mask2, to: CGSize(width: width, height: height)) else {
            print("❌ Failed to resize masks")
            return nil
        }
        
        guard let cgImage1 = resizedMask1.cgImage,
              let cgImage2 = resizedMask2.cgImage else {
            print("❌ Failed to get CGImages from resized masks")
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
        
        return UIImage(cgImage: intersectedCGImage, scale: resizedMask1.scale, orientation: resizedMask1.imageOrientation)
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
    
    // MARK: - Pen Drawing Functions
    private func finishDrawing() {
        guard !currentDrawingPath.isEmpty else {
            isDrawing = false
            return
        }
        
        let imageToUse = photo ?? depthImage
        
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: imageToUse.size) {
            maskHistory.append(drawnMask)
            maskImage = recompositeMaskHistory()
            showConfirmButton = true
        }
        
        currentDrawingPath = []
        isDrawing = false
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
