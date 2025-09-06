//
//  OpenCVDepthProcessor.mm
//  TrueDepthVolumeApp
//
//  Created by Jake Adams on 9/6/25.
//

// Include OpenCV headers FIRST before any Apple headers
#include <opencv2/opencv.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/core.hpp>

#import "OpenCVDepthProcessor.h"

@implementation OpenCVDepthProcessor

+ (NSDictionary *)processDepthMap:(NSArray<NSArray<NSNumber *> *> *)depthMapArray
                            width:(int)width
                           height:(int)height {
    
    // Convert NSArray to cv::Mat (EXACT same as notebook)
    cv::Mat depthMap(height, width, CV_32F);
    for (int y = 0; y < height; y++) {
        NSArray<NSNumber *> *row = depthMapArray[y];
        for (int x = 0; x < width; x++) {
            depthMap.at<float>(y, x) = [row[x] floatValue];
        }
    }
    
    // Fill holes using inpainting (EXACT same as notebook)
    cv::Mat mask = cv::Mat::zeros(height, width, CV_8U);
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            if (depthMap.at<float>(y, x) == 0) {
                mask.at<uchar>(y, x) = 255;
            }
        }
    }
    
    if (cv::countNonZero(mask) > 0) {
        cv::inpaint(depthMap, mask, depthMap, 3, cv::INPAINT_TELEA);
    }
    
    // Apply Gaussian smoothing (EXACT same parameters as notebook)
    cv::Mat smoothed;
    cv::GaussianBlur(depthMap, smoothed, cv::Size(5, 5), 1.0);
    
    // Calculate gradients using Sobel operators (EXACT same as notebook)
    cv::Mat gradX, gradY;
    cv::Sobel(smoothed, gradX, CV_64F, 1, 0, 3);
    cv::Sobel(smoothed, gradY, CV_64F, 0, 1, 3);
    
    // Gradient magnitude (EXACT same as notebook)
    cv::Mat gradientMagnitude;
    cv::magnitude(gradX, gradY, gradientMagnitude);
    
    // Adaptive threshold (EXACT same logic as notebook - top 15%)
    cv::Mat edgeMask = cv::Mat::zeros(height, width, CV_8U);
    
    // Find valid gradients
    std::vector<double> validGradients;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            double grad = gradientMagnitude.at<double>(y, x);
            if (grad > 0) {
                validGradients.push_back(grad);
            }
        }
    }
    
    if (!validGradients.empty()) {
        // Calculate 85th percentile (top 15% threshold - EXACT same as notebook)
        std::sort(validGradients.begin(), validGradients.end());
        int thresholdIndex = (int)(validGradients.size() * 0.85);
        double threshold = validGradients[thresholdIndex];
        
        // Apply threshold
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                if (gradientMagnitude.at<double>(y, x) > threshold) {
                    edgeMask.at<uchar>(y, x) = 255;
                }
            }
        }
    }
    
    // Morphological closing (EXACT same as notebook)
    cv::Mat kernel = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
    cv::Mat cleanedEdges;
    cv::morphologyEx(edgeMask, cleanedEdges, cv::MORPH_CLOSE, kernel);
    
    // Find contours (EXACT same as notebook)
    std::vector<std::vector<cv::Point>> contours;
    cv::findContours(cleanedEdges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);
    
    // Filter contours by area and aspect ratio (EXACT same logic as notebook)
    std::vector<std::vector<cv::Point>> validContours;
    double minArea = (width * height) * 0.001; // At least 0.1% of image
    
    for (const auto& contour : contours) {
        double area = cv::contourArea(contour);
        if (area > minArea) {
            cv::Rect boundingRect = cv::boundingRect(contour);
            double aspectRatio = (double)boundingRect.width / boundingRect.height;
            if (aspectRatio > 0.2 && aspectRatio < 5.0) { // Reasonable aspect ratio
                validContours.push_back(contour);
            }
        }
    }
    
    // Get largest contour (EXACT same as notebook)
    std::vector<cv::Point> largestContour;
    if (!validContours.empty()) {
        double maxArea = 0;
        for (const auto& contour : validContours) {
            double area = cv::contourArea(contour);
            if (area > maxArea) {
                maxArea = area;
                largestContour = contour;
            }
        }
    }
    
    // Convert results to iOS types
    UIImage *edgeImage = [self matToUIImage:cleanedEdges];
    NSMutableArray<NSValue *> *contourPoints = [[NSMutableArray alloc] init];
    
    for (const cv::Point& point : largestContour) {
        CGPoint cgPoint = CGPointMake(point.x, point.y);
        [contourPoints addObject:[NSValue valueWithCGPoint:cgPoint]];
    }
    
    return @{
        @"edgeImage": edgeImage ?: [UIImage new],
        @"contour": contourPoints
    };
}

+ (UIImage *)matToUIImage:(cv::Mat)mat {
    NSData *data = [NSData dataWithBytes:mat.data length:mat.elemSize() * mat.total()];
    CGColorSpaceRef colorSpace;
    
    if (mat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(mat.cols, mat.rows, 8, 8 * mat.elemSize(),
                                       mat.step[0], colorSpace, kCGImageAlphaNone,
                                       provider, NULL, false, kCGRenderingIntentDefault);
    
    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    return finalImage;
}

@end
