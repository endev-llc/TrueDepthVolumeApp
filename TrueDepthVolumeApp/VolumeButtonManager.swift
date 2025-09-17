//
//  VolumeButtonManager.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/17/25.
//


import Foundation
import AVFoundation
import MediaPlayer

// MARK: - Volume Button Manager
class VolumeButtonManager: NSObject, ObservableObject {
    @Published var volumePressed = false
    
    private var initialVolume: Float = 0.0
    private var volumeView: MPVolumeView?
    
    func setupVolumeMonitoring() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
        
        initialVolume = AVAudioSession.sharedInstance().outputVolume
        
        AVAudioSession.sharedInstance().addObserver(
            self,
            forKeyPath: "outputVolume",
            options: [.new, .old],
            context: nil
        )
    }
    
    func stopVolumeMonitoring() {
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume" {
            guard let change = change,
                  let newValue = change[.newKey] as? Float,
                  let oldValue = change[.oldKey] as? Float else { return }
            
            if newValue > oldValue {
                DispatchQueue.main.async {
                    self.volumePressed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.volumePressed = false
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let volumeSlider = self.getVolumeSlider() {
                        volumeSlider.value = oldValue
                    }
                }
            }
        }
    }
    
    private func getVolumeSlider() -> UISlider? {
        let volumeView = MPVolumeView()
        for subview in volumeView.subviews {
            if let slider = subview as? UISlider {
                return slider
            }
        }
        return nil
    }
    
    deinit {
        stopVolumeMonitoring()
    }
}