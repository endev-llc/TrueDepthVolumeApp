//
//  PocketScaleMockupView.swift
//  landing-page-mockups
//
//  Created by Jake Adams on 6/16/25.
//

import SwiftUI

struct PocketScaleMockupView: View {
    @State private var isWeighing = false
    @State private var showWeight = false
    @State private var currentWeight = 0.0
    @State private var scaleLines: [Double] = []
    
    var body: some View {
        ZStack {
            // Sophisticated gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground).opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Minimal header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PocketScale")
                            .font(.system(size: 28, weight: .light, design: .default))
                            .foregroundColor(.primary)
                        Text("Digital Food Scale")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .ultraLight))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
                
                // Instructional text (only when not weighing and not showing results)
                if !isWeighing && !showWeight {
                    Text("Center item in camera view")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.bottom, 24)
                }
                
                // Digital scale platform area
                ZStack {
                    // Scale platform background with subtle scale-like styling
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        .shadow(color: .black.opacity(0.05), radius: 40, x: 0, y: 20)
                        .frame(width: 320, height: 320)
                    
                    // Strawberries image filling the entire rounded rectangle
                    Image("strawberries")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 320, height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .scaleEffect(isWeighing ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.5), value: isWeighing)
                    
                    // Scale platform border with subtle gradient
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [Color(.quaternaryLabel), Color(.quaternaryLabel).opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .frame(width: 320, height: 320)
                    
                    // Scale weighing surface pattern (more scale-like)
                    ZStack {
                        // Concentric circles for scale-like appearance
                        ForEach([60, 120, 180, 240], id: \.self) { diameter in
                            Circle()
                                .stroke(Color(.tertiaryLabel).opacity(0.1), lineWidth: 0.5)
                                .frame(width: CGFloat(diameter), height: CGFloat(diameter))
                        }
                        
                        // Radial measurement marks
                        ForEach(0..<8, id: \.self) { index in
                            Rectangle()
                                .fill(Color(.tertiaryLabel).opacity(isWeighing ? 0.4 : 0.1))
                                .frame(width: 1, height: 12)
                                .offset(y: -100)
                                .rotationEffect(.degrees(Double(index) * 45))
                                .animation(.easeInOut(duration: 0.6).delay(Double(index) * 0.1), value: isWeighing)
                        }
                        
                        // Center measurement grid (refined)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 5), spacing: 20) {
                            ForEach(0..<25, id: \.self) { index in
                                Circle()
                                    .fill(Color(.tertiaryLabel))
                                    .frame(width: isWeighing ? 2.5 : 1.5, height: isWeighing ? 2.5 : 1.5)
                                    .opacity(isWeighing ? 0.6 : 0.12)
                                    .scaleEffect(isWeighing ? 1.0 : 0.8)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .delay(Double(index) * 0.03),
                                        value: isWeighing
                                    )
                            }
                        }
                        .frame(width: 140, height: 140)
                    }
                    
                    // Status display during weighing
                    if isWeighing {
                        VStack(spacing: 8) {
                            Text("Analyzing...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            
                            // Progress indicator
                            HStack(spacing: 4) {
                                ForEach(0..<4) { index in
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(isWeighing ? 1.0 : 0.5)
                                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                                        .animation(
                                            .easeInOut(duration: 0.5)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                            value: isWeighing
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
                
                // Accuracy indicator (only when not weighing and not showing results)
                if !isWeighing && !showWeight {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        Text("±0.1g precision")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 24)
                }
                
                // Weight results panel
                if showWeight {
                    VStack(spacing: 24) {
                        // Status indicator
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("Measurement Complete")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        
                        // Primary weight display - improved readability
                        HStack(alignment: .bottom, spacing: 8) {
                            Text("\(String(format: "%.1f", currentWeight))")
                                .font(.system(size: 58, weight: .light, design: .rounded))
                                .foregroundColor(.primary)
                                .kerning(-1)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("oz")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("(\(String(format: "%.0f", currentWeight * 28.35))g)")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                            .offset(y: -10)
                            
                            Spacer()
                        }
                        
                        // Metadata
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ITEM")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .tracking(1)
                                    Text("Fresh Strawberries")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("ACCURACY")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .tracking(1)
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("97%")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            
                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: {}) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 16))
                                        Text("Save Weight")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.blue)
                                    .cornerRadius(14)
                                }
                                
                                Button(action: {
                                    withAnimation(.spring()) {
                                        showWeight = false
                                        isWeighing = false
                                    }
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.blue)
                                        .frame(width: 50, height: 50)
                                        .background(Color(.tertiarySystemBackground))
                                        .cornerRadius(14)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .cornerRadius(24)
                    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                
                Spacer()
                
                // Elegant Tap to Weigh button (when not showing results)
                if !showWeight {
                    Button(action: startMeasurement) {
                        HStack(spacing: 12) {
                            if isWeighing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Measuring...")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "scale.3d")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Tap to Weigh")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        .scaleEffect(isWeighing ? 0.98 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isWeighing)
                    }
                    .disabled(isWeighing)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            // Auto-demo after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                startMeasurement()
            }
        }
    }
    
    private func startMeasurement() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isWeighing = true
        }
        
        // Simulate measurement process
        let startTime = Date()
        
        func updateWeight() {
            let elapsed = Date().timeIntervalSince(startTime)
            
            if elapsed < 2.8 {
                currentWeight = Double.random(in: 5.8...6.4)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateWeight()
                }
            } else {
                currentWeight = 13.1
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    isWeighing = false
                    showWeight = true
                }
            }
        }
        
        updateWeight()
    }
}

#Preview {
    PocketScaleMockupView()
}
