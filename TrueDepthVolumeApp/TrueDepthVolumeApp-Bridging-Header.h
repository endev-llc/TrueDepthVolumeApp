//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

// Include OpenCV headers BEFORE any Apple headers to avoid macro conflicts
#ifdef __cplusplus
#include <opencv2/opencv.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/core.hpp>
#endif

#import "OpenCVDepthProcessor.h"
