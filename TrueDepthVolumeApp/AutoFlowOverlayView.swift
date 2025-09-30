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
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    @State private var showConfirmButton = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header controls
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Text("Select Primary Object")
                        .foregroundColor(.white)
                        .font(.headline)
                    
                    Spacer()
                    
                    if !showingDepthOnly && photo != nil {
                        Button(showingDepthOnly ? "Show Both" : "Depth Only") {
                            showingDepthOnly.toggle()
                        }
                        .foregroundColor(.white)
                        .padding()
                    }
                    
                    // Clear masks button
                    if maskImage != nil && !showConfirmButton {
                        Button("Clear") {
                            maskImage = nil
                            tapLocation = .zero
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal)
                    }
                    
                    if showConfirmButton {
                        Button("Confirm") {
                            cropCSVWithMask()
                        }
                        .foregroundColor(.green)
                        .padding()
                    } else if maskImage == nil {
                        // Placeholder for spacing
                        Text("")
                            .padding()
                    }
                }
                .frame(height: 44)
                
                // Opacity slider (only show if photo exists and not depth only)
                if !showingDepthOnly && photo != nil {
                    HStack {
                        Text("Photo Opacity:")
                            .foregroundColor(.white)
                        Slider(value: $photoOpacity, in: 0...1)
                            .accentColor(.blue)
                        Text("\(Int(photoOpacity * 100))%")
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal)
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
                        
                        // Tap indicator for auto-segmentation
                        if tapLocation != .zero {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleAutoSegmentTap(at: location)
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
        if !isImageEncoded {
            return "Encoding image for AI segmentation..."
        } else if maskImage == nil {
            return "Tap anywhere on the primary object you want to measure."
        } else {
            return "AI mask applied! Tap more areas to add to mask, or tap 'Confirm' when done."
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
                    // Composite masks instead of replacing
                    self.maskImage = compositeMasks(self.maskImage, with: mask)
                    self.showConfirmButton = true
                }
            }
        }
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
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    @State private var showConfirmButton = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header controls
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Text("Refine Contents")
                        .foregroundColor(.yellow)
                        .font(.headline)
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button("Skip") {
                            onSkip()
                        }
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        
                        // Clear masks button
                        if maskImage != nil && !showConfirmButton {
                            Button("Clear") {
                                maskImage = nil
                                tapLocation = .zero
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal)
                        }
                        
                        if showConfirmButton {
                            Button("Confirm") {
                                applyRefinementMask()
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal)
                        }
                    }
                }
                .frame(height: 44)
                
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
                        
                        // Tap indicator
                        if tapLocation != .zero {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .position(tapLocation)
                                .animation(.easeInOut(duration: 0.3), value: tapLocation)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleRefinementTap(at: location)
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
        if !isImageEncoded {
            return "Encoding image for refinement..."
        } else if maskImage == nil {
            return "Tap the food contents you want to isolate, or tap 'Skip' to use the full primary object."
        } else {
            return "Mask applied! Tap more areas to add, or tap 'Confirm' to apply or 'Skip' to use the full primary object."
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
                    // Composite masks instead of replacing
                    self.maskImage = compositeMasks(self.maskImage, with: mask)
                    self.showConfirmButton = true
                }
            }
        }
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
