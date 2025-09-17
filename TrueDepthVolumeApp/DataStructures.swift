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
    let fx: Float     // Focal length X
    let fy: Float     // Focal length Y
    let cx: Float     // Principal point X
    let cy: Float     // Principal point Y
    let width: Float  // Reference width
    let height: Float // Reference height
}

// MARK: - Volume Information Structure
struct VoxelVolumeInfo {
    let totalVolume: Double  // in cubic meters
    let voxelCount: Int
    let voxelSize: Float     // in meters
}
