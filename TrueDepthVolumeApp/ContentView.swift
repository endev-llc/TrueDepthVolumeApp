//
//  ContentView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var samManager = try! MobileSAMManager()
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var imageViewSize: CGSize = .zero
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            VStack {
                if let image = selectedImage {
                    // Image display with overlay
                    ZStack {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .onAppear {
                                    print("🖥️ [UI] Image appeared with geometry: \(geometry.size)")
                                    imageViewSize = geometry.size
                                    print("🖥️ [UI] Image view size updated to: \(imageViewSize)")
                                }
                                .onTapGesture { location in
                                    print("👆 [GESTURE] Image tapped at location: \(location)")
                                    print("👆 [GESTURE] View size: \(geometry.size)")
                                    print("👆 [GESTURE] Image size: \(image.size)")
                                    handleImageTap(at: location, in: geometry.size, image: image)
                                }
                        }
                        
                        // Mask overlay
                        if let maskImage = samManager.currentMask {
                            GeometryReader { geometry in
                                Image(uiImage: maskImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .allowsHitTesting(false)
                                    .onAppear {
                                        print("🖥️ [UI] Mask overlay appeared")
                                        print("🖥️ [UI] Displaying mask overlay with size: \(maskImage.size)")
                                    }
                            }
                        }
                        
                        // Loading overlay
                        if samManager.isProcessing {
                            Color.black.opacity(0.3)
                                .overlay(
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.5)
                                            .onAppear {
                                                print("🖥️ [UI] Progress view appeared")
                                                print("🖥️ [UI] Showing processing overlay")
                                            }
                                        Text("Processing...")
                                            .foregroundColor(.white)
                                            .padding(.top, 8)
                                    }
                                )
                        }
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                    .clipped()
                    .onAppear {
                        print("🖥️ [UI] Image container appeared")
                        print("🖥️ [UI] Displaying selected image with size: \(image.size)")
                    }
                    
                    // Instructions
                    VStack(spacing: 8) {
                        Text("Tap anywhere on the image to segment objects")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .onAppear {
                                print("🖥️ [UI] Instructions text appeared")
                            }
                        
                        if samManager.currentMask != nil {
                            Text("Red overlay shows the segmented object")
                                .font(.caption)
                                .foregroundColor(.red)
                                .onAppear {
                                    print("🖥️ [UI] Mask description text appeared")
                                }
                        }
                    }
                    .padding()
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button("Clear Mask") {
                            print("🔄 [ACTION] Clear mask button tapped")
                            samManager.currentMask = nil
                            print("🔄 [ACTION] Mask cleared")
                        }
                        .buttonStyle(.bordered)
                        .disabled(samManager.currentMask == nil)
                        .onAppear {
                            print("🖥️ [UI] Clear mask button appeared")
                        }
                        
                        Button("Select Image") {
                            print("📸 [ACTION] Select image button tapped")
                            showingImagePicker = true
                            print("📸 [ACTION] Image picker will be shown")
                        }
                        .buttonStyle(.bordered)
                        .onAppear {
                            print("🖥️ [UI] Select image button appeared")
                        }
                    }
                    
                } else {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "photo")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                            .onAppear {
                                print("🖥️ [UI] Empty state photo icon appeared")
                            }
                        
                        Text("Select an image to start segmentation")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .onAppear {
                                print("🖥️ [UI] Empty state text appeared")
                            }
                        
                        Button("Choose Image") {
                            print("📸 [ACTION] Choose image button tapped")
                            showingImagePicker = true
                            print("📸 [ACTION] Image picker will be shown")
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.headline)
                        .onAppear {
                            print("🖥️ [UI] Choose image button appeared")
                        }
                    }
                    .padding()
                    .onAppear {
                        print("🖥️ [UI] Displaying empty state")
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Mobile SAM")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .alert("Error", isPresented: $showingAlert) {
                Button("OK") {
                    print("❌ [ALERT] Error alert OK button tapped")
                    samManager.errorMessage = nil
                    print("❌ [ALERT] Error message cleared")
                }
            } message: {
                Text(samManager.errorMessage ?? "Unknown error occurred")
            }
            .onChange(of: samManager.errorMessage) { errorMessage in
                print("❌ [OBSERVER] Error message changed: \(String(describing: errorMessage))")
                showingAlert = errorMessage != nil
                print("❌ [OBSERVER] Alert state updated: \(showingAlert)")
            }
            .onChange(of: selectedImage) { newImage in
                print("📸 [OBSERVER] Selected image changed")
                if let image = newImage {
                    print("📸 [OBSERVER] New image size: \(image.size)")
                } else {
                    print("📸 [OBSERVER] Image cleared")
                }
                
                // Clear previous mask when new image is selected
                print("🔄 [OBSERVER] Clearing previous mask")
                samManager.currentMask = nil
                print("🔄 [OBSERVER] Mask cleared")
            }
            .onAppear {
                print("🖥️ [UI] ContentView appeared")
            }
        }
        .onAppear {
            print("🖥️ [UI] NavigationView appeared")
            print("🖥️ [UI] ContentView body rendering...")
        }
    }
    
    private func handleImageTap(at location: CGPoint, in viewSize: CGSize, image: UIImage) {
        print("\n👆 [TAP] Handling image tap...")
        print("👆 [TAP] Tap location: \(location)")
        print("👆 [TAP] View size: \(viewSize)")
        print("👆 [TAP] Image size: \(image.size)")
        
        // Convert tap location to image coordinates
        let imageCoordinates = convertViewCoordinatesToImageCoordinates(
            tapLocation: location,
            viewSize: viewSize,
            imageSize: image.size
        )
        
        print("👆 [TAP] Converted image coordinates: \(imageCoordinates)")
        
        // Trigger segmentation
        print("👆 [TAP] Triggering segmentation...")
        samManager.segment(image: image, clickPoint: imageCoordinates)
        print("👆 [TAP] Segmentation request sent")
    }
    
    private func convertViewCoordinatesToImageCoordinates(
        tapLocation: CGPoint,
        viewSize: CGSize,
        imageSize: CGSize
    ) -> CGPoint {
        print("\n🔄 [CONVERT] Converting view coordinates to image coordinates...")
        print("🔄 [CONVERT] Tap location: \(tapLocation)")
        print("🔄 [CONVERT] View size: \(viewSize)")
        print("🔄 [CONVERT] Image size: \(imageSize)")
        
        // Calculate how the image is displayed (aspect fit)
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        print("🔄 [CONVERT] Image aspect ratio: \(imageAspectRatio)")
        print("🔄 [CONVERT] View aspect ratio: \(viewAspectRatio)")
        
        var displayedImageSize: CGSize
        var imageOffset: CGPoint = .zero
        
        if imageAspectRatio > viewAspectRatio {
            print("🔄 [CONVERT] Image is wider than view - fitting to width")
            // Image is wider than view - fit to width
            displayedImageSize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspectRatio
            )
            imageOffset = CGPoint(
                x: 0,
                y: (viewSize.height - displayedImageSize.height) / 2
            )
        } else {
            print("🔄 [CONVERT] Image is taller than view - fitting to height")
            // Image is taller than view - fit to height
            displayedImageSize = CGSize(
                width: viewSize.height * imageAspectRatio,
                height: viewSize.height
            )
            imageOffset = CGPoint(
                x: (viewSize.width - displayedImageSize.width) / 2,
                y: 0
            )
        }
        
        print("🔄 [CONVERT] Displayed image size: \(displayedImageSize)")
        print("🔄 [CONVERT] Image offset: \(imageOffset)")
        
        // Convert tap location to coordinates within the displayed image
        let relativeLocation = CGPoint(
            x: tapLocation.x - imageOffset.x,
            y: tapLocation.y - imageOffset.y
        )
        
        print("🔄 [CONVERT] Relative location: \(relativeLocation)")
        
        // Ensure the tap is within the displayed image bounds
        let isWithinBounds = relativeLocation.x >= 0 && relativeLocation.x <= displayedImageSize.width &&
                           relativeLocation.y >= 0 && relativeLocation.y <= displayedImageSize.height
        
        print("🔄 [CONVERT] Is within bounds: \(isWithinBounds)")
        
        guard isWithinBounds else {
            print("⚠️ [CONVERT] Tap is outside image bounds, returning zero point")
            return CGPoint.zero
        }
        
        // Scale to original image coordinates
        let scaleX = imageSize.width / displayedImageSize.width
        let scaleY = imageSize.height / displayedImageSize.height
        
        print("🔄 [CONVERT] Scale factors - X: \(scaleX), Y: \(scaleY)")
        
        let finalCoordinates = CGPoint(
            x: relativeLocation.x * scaleX,
            y: relativeLocation.y * scaleY
        )
        
        print("🔄 [CONVERT] Final image coordinates: \(finalCoordinates)")
        print("✅ [CONVERT] Coordinate conversion completed")
        
        return finalCoordinates
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        print("📸 [PICKER] Creating UIImagePickerController")
        
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        
        print("📸 [PICKER] UIImagePickerController configured")
        print("📸 [PICKER] Source type: \(picker.sourceType.rawValue)")
        print("📸 [PICKER] Allows editing: \(picker.allowsEditing)")
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        print("📸 [PICKER] updateUIViewController called")
    }
    
    func makeCoordinator() -> Coordinator {
        print("📸 [PICKER] Creating coordinator")
        return Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            print("📸 [COORDINATOR] Initializing coordinator")
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            print("📸 [COORDINATOR] Image picker finished with info:")
            print("📸 [COORDINATOR] Info keys: \(info.keys)")
            
            if let image = info[.originalImage] as? UIImage {
                print("📸 [COORDINATOR] Original image found")
                print("📸 [COORDINATOR] Image size: \(image.size)")
                print("📸 [COORDINATOR] Image scale: \(image.scale)")
                
                parent.selectedImage = image
                print("📸 [COORDINATOR] Image assigned to parent")
            } else {
                print("❌ [COORDINATOR] No original image found in info")
            }
            
            print("📸 [COORDINATOR] Dismissing picker")
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("📸 [COORDINATOR] Image picker was cancelled")
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

#Preview {
    print("🖥️ [PREVIEW] ContentView preview rendering")
    return ContentView()
}
