//
//  SmartCal.swift
//  landing-page-mockups
//
//  Created by Assistant on 6/18/25.
//

import SwiftUI

struct SmartCal: View {
    @State private var isScanning = false
    @State private var showNutrition = false
    @State private var scanProgress: CGFloat = 0
    @State private var detectedComponents: [String] = []
    @State private var showingComponents = false
    
    // Nutrition data for demo
    @State private var calories: Int = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var fiber: Double = 0
    @State private var sugar: Double = 0
    @State private var sodium: Int = 0
    @State private var caloriedensity: Double = 0
    
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
                        Text("SmartCal")
                            .font(.system(size: 28, weight: .light, design: .default))
                            .foregroundColor(.primary)
                        Text("Precision Calorie Scanner")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Image(systemName: "camera.metering.spot")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        
                        Button(action: {}) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20, weight: .ultraLight))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
                
                // Instructional text
                if !isScanning && !showNutrition {
                    VStack(spacing: 6) {
                        Text("Point camera at food")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Text("LiDAR + AI Analysis")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 16)
                }
                
                // Scanner viewport - reduced size
                ZStack {
                    // Camera view background
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
                        .shadow(color: .black.opacity(0.05), radius: 40, x: 0, y: 20)
                        .frame(width: 280, height: 280)
                    
                    // Food image
                    Image("strawberries")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 280, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .scaleEffect(isScanning ? 1.02 : 1.0)
                        .animation(.easeInOut(duration: 0.5), value: isScanning)
                    
                    // Scanner overlay
                    if isScanning {
                        // LiDAR depth grid animation
                        ZStack {
                            // Volumetric analysis grid
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                                ForEach(0..<49, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color.green.opacity(0.6), lineWidth: 1)
                                        .frame(width: 32, height: 32)
                                        .opacity(scanProgress > Double(index) / 49.0 ? 1.0 : 0.3)
                                        .scaleEffect(scanProgress > Double(index) / 49.0 ? 1.0 : 0.8)
                                        .animation(
                                            .easeOut(duration: 0.3),
                                            value: scanProgress
                                        )
                                }
                            }
                            .frame(width: 250, height: 250)
                            
                            // Scanning status
                            VStack(spacing: 10) {
                                Text("Analyzing Volume")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                
                                // Progress bar
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 140, height: 5)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.green)
                                        .frame(width: 140 * scanProgress, height: 5)
                                        .animation(.linear(duration: 2.5), value: scanProgress)
                                }
                                
                                if showingComponents {
                                    VStack(spacing: 3) {
                                        ForEach(detectedComponents, id: \.self) { component in
                                            Text("✓ \(component)")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.white)
                                                .shadow(color: .black.opacity(0.8), radius: 1, x: 0, y: 1)
                                                .transition(.opacity.combined(with: .scale))
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                            }
                            .padding(16)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(14)
                        }
                    }
                    
                    // Viewport border
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [Color(.quaternaryLabel), Color(.quaternaryLabel).opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .frame(width: 280, height: 280)
                }
                .padding(.bottom, 20)
                
                // Accuracy indicators
                if !isScanning && !showNutrition {
                    HStack(spacing: 20) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.metering.multispot")
                                .foregroundColor(.green)
                                .font(.system(size: 13))
                            Text("3D Volume")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 13))
                            Text("USDA Verified")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Nutrition results panel
                if showNutrition {
                    VStack(spacing: 12) {
                        // Calorie density score
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CALORIE DENSITY")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                HStack(alignment: .bottom, spacing: 3) {
                                    Text("\(String(format: "%.0f", caloriedensity))")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(caloriedensity < 100 ? .green : caloriedensity < 200 ? .orange : .red)
                                    Text("cal/100g")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .offset(y: -4)
                                }
                            }
                            
                            Spacer()
                            
                            // Total calories
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("TOTAL")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                HStack(alignment: .bottom, spacing: 2) {
                                    Text("\(calories)")
                                        .font(.system(size: 42, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                    Text("cal")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .offset(y: -6)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        // Nutrition facts label - more compact
                        VStack(spacing: 0) {
                            // Header
                            VStack(spacing: 1) {
                                Text("Nutrition Facts")
                                    .font(.system(size: 22, weight: .black))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    Text("Serving size")
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text("370g")
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .padding(.top, 1)
                            }
                            .padding(.bottom, 3)
                            
                            Divider()
                                .background(Color.primary)
                                .frame(height: 5)
                            
                            // Calories section
                            HStack {
                                Text("Calories")
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                                Text("\(calories)")
                                    .font(.system(size: 22, weight: .black))
                            }
                            .padding(.vertical, 3)
                            
                            Divider()
                                .background(Color.primary)
                                .frame(height: 3)
                            
                            // Macros - more compact
                            VStack(spacing: 0) {
                                NutritionRow(label: "Total Fat", value: "\(String(format: "%.1f", fat))g", dailyValue: Int((fat / 78) * 100))
                                Divider()
                                NutritionRow(label: "Total Carbohydrate", value: "\(String(format: "%.1f", carbs))g", dailyValue: Int((carbs / 275) * 100))
                                Divider().padding(.leading, 16)
                                NutritionRow(label: "Dietary Fiber", value: "\(String(format: "%.1f", fiber))g", dailyValue: Int((fiber / 28) * 100), indent: true)
                                Divider().padding(.leading, 16)
                                NutritionRow(label: "Total Sugars", value: "\(String(format: "%.1f", sugar))g", dailyValue: nil, indent: true)
                                Divider()
                                NutritionRow(label: "Protein", value: "\(String(format: "%.1f", protein))g", dailyValue: Int((protein / 50) * 100))
                                
                                Divider()
                                    .background(Color.primary)
                                    .frame(height: 5)
                                    .padding(.top, 1)
                                
                                NutritionRow(label: "Sodium", value: "\(sodium)mg", dailyValue: Int((Double(sodium) / 2300) * 100))
                            }
                            .padding(.top, 1)
                        }
                        .padding(12)
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(.separator), lineWidth: 1)
                        )
                        
                        // Action buttons
                        HStack(spacing: 10) {
                            Button(action: {}) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.app.fill")
                                        .font(.system(size: 15))
                                    Text("Log Food")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                withAnimation(.spring()) {
                                    showNutrition = false
                                    isScanning = false
                                    showingComponents = false
                                    detectedComponents = []
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 15))
                                    Text("Scan Again")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.gray)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                
                Spacer()
                
                // Scan button
                if !showNutrition {
                    Button(action: startScanning) {
                        HStack(spacing: 10) {
                            if isScanning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                                Text("Analyzing...")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "viewfinder.circle.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                Text("Scan Food")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
                        .scaleEffect(isScanning ? 0.98 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isScanning)
                    }
                    .disabled(isScanning)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            // Auto-demo after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                startScanning()
            }
        }
    }
    
    private func startScanning() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isScanning = true
            scanProgress = 0
        }
        
        // Animate scan progress
        withAnimation(.linear(duration: 2.5)) {
            scanProgress = 1.0
        }
        
        // Show detected components
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.spring()) {
                showingComponents = true
            }
            
            let components = ["Fresh Strawberries", "Natural Sugars", "Vitamin C", "Dietary Fiber"]
            for (index, component) in components.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(index) * 0.2) {
                    withAnimation(.spring()) {
                        detectedComponents.append(component)
                    }
                }
            }
        }
        
        // Show results after scanning
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // Set nutrition data for strawberries
            calories = 118
            protein = 2.5
            carbs = 28.5
            fat = 1.1
            fiber = 7.4
            sugar = 18.1
            sodium = 4
            caloriedensity = 32  // per 100g
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isScanning = false
                showNutrition = true
            }
        }
    }
}

struct NutritionRow: View {
    let label: String
    let value: String
    let dailyValue: Int?
    var indent: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: dailyValue != nil ? .bold : .semibold))
                .padding(.leading, indent ? 16 : 0)
            
            Spacer()
            
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                
                if let dv = dailyValue {
                    Text("\(dv)%")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    SmartCal()
}
