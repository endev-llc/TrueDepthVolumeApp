//
//  MobileSAMView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import SwiftUI
import PhotosUI
import UIKit

// MARK: - Mask Compositing Helper
func compositeMasks(_ existingMask: UIImage?, with newMask: UIImage) -> UIImage {
    guard let existing = existingMask else { return newMask }
    
    // Use the larger of the two sizes to ensure we capture both masks
    let size = CGSize(
        width: max(existing.size.width, newMask.size.width),
        height: max(existing.size.height, newMask.size.height)
    )
    
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    defer { UIGraphicsEndImageContext() }
    
    // Draw existing mask
    existing.draw(in: CGRect(origin: .zero, size: existing.size))
    
    // Draw new mask on top (pixels will combine/overlap)
    newMask.draw(in: CGRect(origin: .zero, size: newMask.size), blendMode: .normal, alpha: 1.0)
    
    let compositedMask = UIGraphicsGetImageFromCurrentImageContext()
    
    return compositedMask ?? newMask
}

struct MobileSAMView: View {
    @StateObject private var samManager = MobileSAMManager()
    @State private var selectedImage: UIImage?
    @State private var isImagePickerPresented = false
    @State private var maskImage: UIImage?
    @State private var tapLocation: CGPoint = .zero
    @State private var imageDisplaySize: CGSize = .zero
    @State private var isImageEncoded = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    
                    if let image = selectedImage {
                        imageDisplayView(image: image, in: geometry)
                    } else {
                        imageSelectionView
                    }
                    
                    // Loading overlay
                    if samManager.isLoading {
                        loadingOverlay
                    }
                    
                    // Error message
                    if let errorMessage = samManager.errorMessage {
                        errorMessageView(errorMessage)
                    }
                    
                    // Instructions overlay
                    if selectedImage != nil {
                        instructionsOverlay
                    }
                }
            }
            .navigationTitle("MobileSAM")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    encodeImage(image)
                }
            }
        }
    }
    
    // MARK: - Image Display View
    private func imageDisplayView(image: UIImage, in geometry: GeometryProxy) -> some View {
        let imageAspectRatio = image.size.width / image.size.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        let displaySize: CGSize
        if imageAspectRatio > screenAspectRatio {
            displaySize = CGSize(
                width: geometry.size.width,
                height: geometry.size.width / imageAspectRatio
            )
        } else {
            displaySize = CGSize(
                width: geometry.size.height * imageAspectRatio,
                height: geometry.size.height
            )
        }
        
        // Calculate the actual frame where the image is positioned
        let imageRect = CGRect(
            x: (geometry.size.width - displaySize.width) / 2,
            y: (geometry.size.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        
        return GeometryReader { _ in
            ZStack {
                // Main image - positioned exactly
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .clipped()
                    .onAppear {
                        imageDisplaySize = displaySize
                        debugImageLayout(geometry: geometry, imageSize: image.size)
                    }
                
                // Mask overlay - positioned IDENTICALLY to main image
                if let mask = maskImage {
                    Image(uiImage: mask)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .onAppear {
                            print("Mask displayed - Display size: \(displaySize), Mask size: \(mask.size)")
                        }
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
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleImageTap(at: location, imageRect: imageRect, geometry: geometry)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("New Image") {
                    resetView()
                    isImagePickerPresented = true
                }
            }
        }
    }
    
    // MARK: - Image Selection View
    private var imageSelectionView: some View {
        VStack(spacing: 30) {
            Image(systemName: "photo.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Mobile SAM Segmentation")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Select an image to start segmenting objects with AI")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                isImagePickerPresented = true
            }) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                    Text("Choose Image")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(isImageEncoded ? "Generating mask..." : "Encoding image...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Error Message View
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
    
    // MARK: - Instructions Overlay
    private var instructionsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    if !isImageEncoded {
                        Text("Encoding image...")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    } else {
                        Text("Tap to segment (multiple taps combine)")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        if maskImage != nil {
                            Button("Clear Mask") {
                                maskImage = nil
                                tapLocation = .zero
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    private func handleImageTap(at location: CGPoint, imageRect: CGRect, geometry: GeometryProxy) {
        guard isImageEncoded && !samManager.isLoading else { return }
        
        // Check if tap is within image bounds
        guard imageRect.contains(location) else { return }
        
        // Store the absolute tap location for the red dot indicator
        tapLocation = location
        
        // Convert to relative coordinates within the image
        let relativeX = location.x - imageRect.minX
        let relativeY = location.y - imageRect.minY
        let relativeLocation = CGPoint(x: relativeX, y: relativeY)
        
        Task {
            let mask = await samManager.generateMask(at: relativeLocation, in: imageDisplaySize)
            await MainActor.run {
                if let mask = mask {
                    // CHANGED: Composite instead of replace
                    self.maskImage = compositeMasks(self.maskImage, with: mask)
                }
            }
        }
    }
    
    private func encodeImage(_ image: UIImage) {
        isImageEncoded = false
        maskImage = nil
        tapLocation = .zero
        
        Task {
            let success = await samManager.encodeImage(image)
            await MainActor.run {
                isImageEncoded = success
            }
        }
    }
    
    private func resetView() {
        selectedImage = nil
        maskImage = nil
        tapLocation = .zero
        isImageEncoded = false
        samManager.currentImageEmbeddings = nil
    }
    
    // MARK: - Debug Function
    private func debugImageLayout(geometry: GeometryProxy, imageSize: CGSize) {
        let imageAspectRatio = imageSize.width / imageSize.height
        let screenAspectRatio = geometry.size.width / geometry.size.height
        
        let displaySize: CGSize
        if imageAspectRatio > screenAspectRatio {
            displaySize = CGSize(
                width: geometry.size.width,
                height: geometry.size.width / imageAspectRatio
            )
        } else {
            displaySize = CGSize(
                width: geometry.size.height * imageAspectRatio,
                height: geometry.size.height
            )
        }
        
        let imageRect = CGRect(
            x: (geometry.size.width - displaySize.width) / 2,
            y: (geometry.size.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        
        print("=== DEBUG INFO ===")
        print("Screen size: \(geometry.size)")
        print("Original image size: \(imageSize)")
        print("Display size: \(displaySize)")
        print("Image rect: \(imageRect)")
        print("Image aspect ratio: \(imageAspectRatio)")
        print("Screen aspect ratio: \(screenAspectRatio)")
        print("=================")
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
