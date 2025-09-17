import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import MediaPlayer

// MARK: - Camera View
struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.layer.frame = view.bounds
        previewLayer.frame = view.layer.frame
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.frame = uiView.bounds
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiView: UIActivityViewController, context: Context) {}
}

// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFileURL: URL?
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.commaSeparatedText], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Copy the file to app's documents directory to ensure persistent access
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let destinationURL = documentsDirectory.appendingPathComponent("uploaded_\(url.lastPathComponent)")
            
            do {
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // Copy the selected file
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.parent.selectedFileURL = destinationURL
                }
            } catch {
                print("Error copying CSV file: \(error)")
            }
        }
    }
}

// MARK: - Volume View
struct VolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        return volumeView
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
