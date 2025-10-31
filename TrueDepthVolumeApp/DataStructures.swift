import Foundation
import CoreGraphics

// MARK: - Depth Point Data Structure
struct DepthPoint {
    let x: Float
    let y: Float
    let depth: Float
}

// MARK: - Camera Intrinsics Structure
struct CameraIntrinsics {
    let fx: Float
    let fy: Float
    let cx: Float
    let cy: Float
    let width: Float
    let height: Float
    let depthWidth: Float     // ✅ Required, no optional
    let depthHeight: Float    // ✅ Required, no optional
}

// MARK: - Volume Information Structure
struct VoxelVolumeInfo {
    let totalVolume: Double  // in cubic meters
    let voxelCount: Int
    let voxelSize: Float     // in meters
}
