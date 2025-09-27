//
//  TrueDepthCameraView.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import SwiftUI
import AVFoundation
import MediaPlayer
import CoreGraphics
import UIKit
import UniformTypeIdentifiers

struct TrueDepthCameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var volumeManager = VolumeButtonManager()
    @State private var showOverlayView = false
    @State private var uploadedCSVFile: URL?
    @State private var showDocumentPicker = false

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                CameraView(session: cameraManager.session)
                    .onAppear {
                        cameraManager.startSession()
                        volumeManager.setupVolumeMonitoring()
                    }
                    .onDisappear {
                        cameraManager.stopSession()
                        volumeManager.stopVolumeMonitoring()
                    }
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    Button(action: {
                        cameraManager.captureDepthAndPhoto()
                    }) {
                        Text("Capture Depth + Photo")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(15)
                    }
                    
                    Button(action: {
                        showDocumentPicker = true
                    }) {
                        Text("Upload CSV")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.cyan)
                            .cornerRadius(15)
                    }
                    
                    if cameraManager.isProcessing {
                        Text("Processing...")
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                    }
                    
                    // Show buttons only for uploaded CSV (manual flow)
                    if cameraManager.capturedDepthImage != nil && uploadedCSVFile != nil {
                        HStack(spacing: 15) {
                            Button(action: {
                                showOverlayView = true
                            }) {
                                Text("View Overlay")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.green)
                                    .cornerRadius(15)
                            }
                            
                            // Export button
                            Button(action: {
                                cameraManager.showShareSheet = true
                            }) {
                                Text("Export")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.orange)
                                    .cornerRadius(15)
                            }
                            .disabled(cameraManager.fileToShare == nil && cameraManager.croppedFileToShare == nil)
                        }
                    }
                    
                    // 3D View button (show only for uploaded CSV manual flow)
                    if uploadedCSVFile != nil && cameraManager.capturedDepthImage == nil {
                        Button(action: {
                            cameraManager.show3DView = true
                        }) {
                            Text("View 3D")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.purple)
                                .cornerRadius(15)
                        }
                    }
                    
                    if let lastSavedFile = cameraManager.lastSavedFileName {
                        Text("Saved: \(lastSavedFile)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(10)
                    }
                }
                .padding(.bottom, 50)
                
                // Hidden volume view for capturing volume button presses
                VolumeView()
            }
            .navigationTitle("3D Volume")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $cameraManager.showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(cameraManager.errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $cameraManager.showShareSheet) {
                // Export cropped CSV if available, otherwise raw CSV
                if let croppedFileURL = cameraManager.croppedFileToShare {
                    ShareSheet(items: [croppedFileURL])
                } else if let fileURL = cameraManager.fileToShare {
                    ShareSheet(items: [fileURL])
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(selectedFileURL: $uploadedCSVFile)
            }
            .fullScreenCover(isPresented: $showOverlayView) {
                if let depthImage = cameraManager.capturedDepthImage {
                    AutoFlowOverlayView(
                        depthImage: depthImage,
                        photo: cameraManager.capturedPhoto,
                        cameraManager: cameraManager,
                        onComplete: { showOverlayView = false }
                    )
                }
            }
            .fullScreenCover(isPresented: $cameraManager.show3DView) {
                if let croppedFileURL = cameraManager.croppedFileToShare {
                    DepthVisualization3DView(
                        csvFileURL: croppedFileURL, cameraManager: cameraManager,
                        onDismiss: {
                            cameraManager.show3DView = false
                            cameraManager.refinementMask = nil
                        }
                    )
                } else if let uploadedCSV = uploadedCSVFile {
                    DepthVisualization3DView(
                        csvFileURL: uploadedCSV, cameraManager: cameraManager,
                        onDismiss: { cameraManager.show3DView = false }
                    )
                }
            }
            .onReceive(volumeManager.$volumePressed) { pressed in
                if pressed {
                    cameraManager.captureDepthAndPhoto()
                }
            }
            .onChange(of: uploadedCSVFile) { _, newFile in
                if let file = newFile {
                    cameraManager.processUploadedCSV(file)
                }
            }
            // AUTOMATIC FLOW: Show overlay immediately after capture
            .onChange(of: cameraManager.capturedDepthImage) { _, newImage in
                if newImage != nil && uploadedCSVFile == nil { // Only for camera captures, not uploaded CSV
                    showOverlayView = true
                }
            }
        }
    }
}
