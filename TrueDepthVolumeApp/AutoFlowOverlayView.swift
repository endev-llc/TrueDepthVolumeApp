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
                        flowState = .completed
                        show3DView = true
                    },
                    onSkip: {
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
                                color: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7)
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
        // Get the actual frame of the rendered image in the container's coordinate space
        let frame = imageGeometry.frame(in: .named("imageContainer"))
        imageFrame = frame
        imageDisplaySize = frame.size
    }
    
    // MARK: - Auto-Segmentation Functions
    private func startAutoSegmentation() {
        maskImage = nil
        maskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        
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
        
        // Convert tap location to relative coordinates within the image
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    // Add to history
                    maskHistory.append(mask)
                    // Recomposite all masks from history
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
        
        // Convert drawn path to mask image
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: imageDisplaySize) {
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
        
        // Set up drawing context
        context.setFillColor(UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 1.0).cgColor)
        
        // Draw circles at each point in the path
        for point in path {
            // Convert from screen coordinates to image coordinates
            let relativeX = (point.x - frame.minX) / frame.width
            let relativeY = (point.y - frame.minY) / frame.height
            
            let imageX = relativeX * size.width
            let imageY = relativeY * size.height
            
            // Scale brush size proportionally to image size
            let scaledBrushSize = brushSize * (size.width / frame.width)
            
            let rect = CGRect(
                x: imageX - scaledBrushSize / 2,
                y: imageY - scaledBrushSize / 2,
                width: scaledBrushSize,
                height: scaledBrushSize
            )
            
            context.fillEllipse(in: rect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
    
    private func cropCSVWithMask() {
        guard let maskImage = maskImage else { return }
        
        cameraManager.cropDepthDataWithMask(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size)
        
        // Wait for cropping to complete and then proceed
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
                        
                        // Drawing overlay (for pen mode)
                        if isPenMode && !currentDrawingPath.isEmpty {
                            PenDrawingOverlay(
                                points: $currentDrawingPath,
                                brushSize: brushSize,
                                color: UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7)
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
        // Get the actual frame of the rendered image in the container's coordinate space
        let frame = imageGeometry.frame(in: .named("refinementContainer"))
        imageFrame = frame
        imageDisplaySize = frame.size
    }
    
    private func startRefinementSegmentation() {
        maskImage = nil
        maskHistory = []
        tapLocation = .zero
        showConfirmButton = false
        isImageEncoded = false
        
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
        
        // Convert tap location to relative coordinates within the image
        let relativeX = location.x - imageFrame.minX
        let relativeY = location.y - imageFrame.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    // Add to history
                    maskHistory.append(mask)
                    // Recomposite all masks from history
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
        
        // Convert drawn path to mask image
        if let drawnMask = createMaskFromPath(currentDrawingPath, brushSize: brushSize, in: imageFrame, imageSize: imageDisplaySize) {
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
        
        // Set up drawing context
        context.setFillColor(UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 1.0).cgColor)
        
        // Draw circles at each point in the path
        for point in path {
            // Convert from screen coordinates to image coordinates
            let relativeX = (point.x - frame.minX) / frame.width
            let relativeY = (point.y - frame.minY) / frame.height
            
            let imageX = relativeX * size.width
            let imageY = relativeY * size.height
            
            // Scale brush size proportionally to image size
            let scaledBrushSize = brushSize * (size.width / frame.width)
            
            let rect = CGRect(
                x: imageX - scaledBrushSize / 2,
                y: imageY - scaledBrushSize / 2,
                width: scaledBrushSize,
                height: scaledBrushSize
            )
            
            context.fillEllipse(in: rect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()
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
    
    private func applyRefinementMask() {
        guard let maskImage = maskImage,
              let primaryCSV = primaryCroppedCSV else { return }
        
        cameraManager.refineWithSecondaryMask(maskImage, imageFrame: imageFrame, depthImageSize: depthImage.size, primaryCroppedCSV: primaryCSV)
        
        // Wait for refinement to complete and then proceed
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            onRefinementComplete()
        }
    }
}

// MARK: - Optimized Pen Drawing Overlay (UIView-based for minimal latency)
struct PenDrawingOverlay: UIViewRepresentable {
    @Binding var points: [CGPoint]
    let brushSize: CGFloat
    let color: UIColor
    
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
        uiView.setNeedsDisplay()
    }
}

class PenDrawingCanvasView: UIView {
    var points: [CGPoint] = []
    var brushSize: CGFloat = 30
    var color: UIColor = UIColor(red: 139/255, green: 69/255, blue: 19/255, alpha: 0.7)
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setFillColor(color.cgColor)
        
        for point in points {
            let rect = CGRect(
                x: point.x - brushSize / 2,
                y: point.y - brushSize / 2,
                width: brushSize,
                height: brushSize
            )
            context.fillEllipse(in: rect)
        }
    }
}
