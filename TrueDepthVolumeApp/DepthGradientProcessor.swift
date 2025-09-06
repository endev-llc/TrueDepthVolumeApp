//
//  DepthGradientProcessor.swift
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/6/25.
//

import Foundation
import UIKit
import CoreGraphics

// Objective-C bridge for OpenCV functions
@objc public class DepthGradientProcessor: NSObject {
    
    @objc public static func processDepthData(
        points: [[NSNumber]], // [[x, y, depth], ...]
        completion: @escaping (UIImage?, [CGPoint]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = performDepthGradientSegmentation(points: points)
            DispatchQueue.main.async {
                completion(result.edgeImage, result.contour)
            }
        }
    }
    
    private static func performDepthGradientSegmentation(points: [[NSNumber]]) -> (edgeImage: UIImage?, contour: [CGPoint]) {
        guard !points.isEmpty else { return (nil, []) }
        
        // Extract coordinates and depths
        var xCoords: [Float] = []
        var yCoords: [Float] = []
        var depths: [Float] = []
        
        for point in points {
            guard point.count >= 3 else { continue }
            let x = point[0].floatValue
            let y = point[1].floatValue
            let depth = point[2].floatValue
            
            if !depth.isNaN && !depth.isInfinite && depth > 0 {
                xCoords.append(x)
                yCoords.append(y)
                depths.append(depth)
            }
        }
        
        guard !xCoords.isEmpty else { return (nil, []) }
        
        // Calculate original depth map dimensions
        let xMin = Int(xCoords.min()!)
        let xMax = Int(xCoords.max()!)
        let yMin = Int(yCoords.min()!)
        let yMax = Int(yCoords.max()!)
        
        let originalWidth = xMax - xMin + 1
        let originalHeight = yMax - yMin + 1
        
        // Create rotated dimensions to match visualization rotation
        let rotatedWidth = originalHeight  // Swap dimensions after rotation
        let rotatedHeight = originalWidth
        
        print("Creating rotated depth map: \(rotatedWidth) x \(rotatedHeight) pixels (rotated from \(originalWidth) x \(originalHeight))")
        
        // Create depth map with rotated dimensions
        var depthMap = Array(repeating: Array(repeating: Float(0), count: rotatedWidth), count: rotatedHeight)
        var countMap = Array(repeating: Array(repeating: Int(0), count: rotatedWidth), count: rotatedHeight)
        
        // Map points to depth map with rotation applied (same as visualization)
        for i in 0..<xCoords.count {
            let originalXIdx = Int(xCoords[i]) - xMin
            let originalYIdx = Int(yCoords[i]) - yMin
            
            // Apply same rotation as visualization: (x,y) -> (originalHeight-1-y, x)
            let rotatedX = originalHeight - 1 - originalYIdx
            let rotatedY = originalXIdx
            
            if rotatedX >= 0 && rotatedX < rotatedWidth && rotatedY >= 0 && rotatedY < rotatedHeight {
                depthMap[rotatedY][rotatedX] += depths[i]
                countMap[rotatedY][rotatedX] += 1
            }
        }
        
        // Average multiple measurements per pixel (EXACT same as notebook)
        for y in 0..<rotatedHeight {
            for x in 0..<rotatedWidth {
                if countMap[y][x] > 0 {
                    depthMap[y][x] /= Float(countMap[y][x])
                }
            }
        }
        
        // Call OpenCV processing with rotated dimensions
        return processWithOpenCV(depthMap: depthMap, width: rotatedWidth, height: rotatedHeight)
    }
    
    private static func processWithOpenCV(depthMap: [[Float]], width: Int, height: Int) -> (edgeImage: UIImage?, contour: [CGPoint]) {
        // Convert [[Float]] to [[NSNumber]] for Objective-C++ compatibility
        let nsDepthMap = depthMap.map { row in
            row.map { NSNumber(value: $0) }
        }
        
        // Call OpenCV processor and handle NSDictionary return
        let result = OpenCVDepthProcessor.processDepthMap(nsDepthMap, width: Int32(width), height: Int32(height))
        
        // Extract values from NSDictionary and convert to expected tuple format
        let edgeImage = result?["edgeImage"] as? UIImage
        let contourValues = result?["contour"] as? [NSValue] ?? []
        
        // Convert NSValue array to CGPoint array
        let contour = contourValues.compactMap { value in
            value.cgPointValue
        }
        
        return (edgeImage: edgeImage, contour: contour)
    }
}
