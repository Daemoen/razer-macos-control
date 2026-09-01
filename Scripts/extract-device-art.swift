#!/usr/bin/env swift
//
// Lifts a device out of a photograph and writes a transparent PNG.
//
// The app needs pictures of real hardware. Drawing hardware from memory in
// Bezier paths produces something that gestures at a device without resembling
// one, and openly-licensed photographs of these particular Razer peripherals do
// not exist. Photographs taken by the person who owns the hardware are the only
// source with no third-party rights attached, so this turns those into assets.
//
// Runs entirely on-device through Vision. Nothing is uploaded.
//
// Usage: swift Scripts/extract-device-art.swift <input> <output.png> [maxDimension] [erodePixels] [dustThreshold] [flattenVariance]

import Foundation
import Vision
import CoreImage
import AppKit
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fail("usage: extract-device-art.swift <input> <output.png> [maxDimension] [erodePixels]")
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let maxDimension = arguments.count > 3 ? (Double(arguments[3]) ?? 1400) : 1400
// Pixels of alpha to pull back from the cut edge.
let erodeRadius = arguments.count > 4 ? (Float(arguments[4]) ?? 2.0) : 2.0
// How far a pixel must deviate from its neighbours to count as dust. Lower is
// more aggressive. 0 disables cleanup.
let dustThreshold = arguments.count > 5 ? (Float(arguments[5]) ?? 0.10) : 0.10
// Luma variance below which a neighbourhood counts as a featureless surface.
// 0 disables surface flattening.
let flattenVariance = arguments.count > 6 ? (Double(arguments[6]) ?? 0) : 0

guard FileManager.default.fileExists(atPath: inputURL.path) else {
    fail("no such file: \(inputURL.path)")
}

let handler = VNImageRequestHandler(url: inputURL, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()

do {
    try handler.perform([request])
} catch {
    fail("Vision request failed: \(error.localizedDescription)")
}

guard let observation = request.results?.first else {
    fail("no foreground subject found -- the device may not be separable from the background")
}

// Crop to the subject's own extent so framing and desk clutter fall away with
// the background rather than having to be trimmed by hand afterwards.
let masked: CVPixelBuffer
do {
    masked = try observation.generateMaskedImage(
        ofInstances: observation.allInstances,
        from: handler,
        croppedToInstancesExtent: true
    )
} catch {
    fail("mask generation failed: \(error.localizedDescription)")
}

var image = CIImage(cvPixelBuffer: masked)

// Eat the edge fringe.
//
// The subject mask lands a pixel or two outside the device, so a rim of desk
// colour survives the cut. Against a dark UI that reads as a bright halo
// tracing the outline -- more damaging than any shadow, because it draws the
// eye to exactly the wrong place. Eroding the alpha channel pulls the boundary
// back inside the object. RGB is left untouched; only coverage moves.
func erodeAlpha(_ source: CIImage, radius: Float) -> CIImage {
    guard radius > 0,
          let toMask = CIFilter(name: "CIColorMatrix") else { return source }
    toMask.setValue(source, forKey: kCIInputImageKey)
    let fromAlpha = CIVector(x: 0, y: 0, z: 0, w: 1)
    toMask.setValue(fromAlpha, forKey: "inputRVector")
    toMask.setValue(fromAlpha, forKey: "inputGVector")
    toMask.setValue(fromAlpha, forKey: "inputBVector")
    toMask.setValue(fromAlpha, forKey: "inputAVector")
    toMask.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
    guard var mask = toMask.outputImage,
          let erode = CIFilter(name: "CIMorphologyMinimum") else { return source }
    erode.setValue(mask, forKey: kCIInputImageKey)
    erode.setValue(radius, forKey: kCIInputRadiusKey)
    mask = (erode.outputImage ?? mask).cropped(to: source.extent)

    guard let blend = CIFilter(name: "CIBlendWithMask") else { return source }
    blend.setValue(source, forKey: kCIInputImageKey)
    blend.setValue(CIImage(color: .clear).cropped(to: source.extent),
                   forKey: kCIInputBackgroundImageKey)
    blend.setValue(mask, forKey: kCIInputMaskImageKey)
    return (blend.outputImage ?? source).cropped(to: source.extent)
}

image = erodeAlpha(image, radius: erodeRadius)

// Downscale to a sane asset size. Phone photos are far larger than any view
// that will draw them, and shipping the full frame wastes bundle space.
let extent = image.extent
let longest = max(extent.width, extent.height)
if longest > maxDimension {
    let factor = maxDimension / longest
    image = image.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
}

let context = CIContext(options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let rendered = context.createCGImage(image, from: image.extent,
                                           format: .RGBA8, colorSpace: colorSpace) else {
    fail("render failed")
}

/// Replace isolated speckles with their local median, and nothing else.
///
/// Deliberately not a blur: a blur takes the grime and the key legends
/// together. A pixel is treated as dirt only when it disagrees with the median
/// of its neighbourhood by more than `threshold`. That is what an isolated
/// speck does; an edge, a legend or the honeycomb texture agrees with enough of
/// its neighbours to survive.
///
/// This runs on the raw buffer rather than through Core Image because the
/// filter-graph version silently applied the median everywhere -- CIBlendWithMask
/// keys off the mask's alpha, and a thresholded mask carries its result in
/// colour with alpha left opaque. Counting the replaced pixels is the check
/// that catches that class of mistake.
func despeckle(_ source: CGImage, threshold: Double, radius: Int) -> (image: CGImage, changed: Int) {
    let width = source.width, height = source.height
    guard width > radius * 2, height > radius * 2 else { return (source, 0) }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let readContext = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else {
        return (source, 0)
    }
    readContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    var output = pixels
    var changed = 0
    let cutoff = threshold * 255.0

    func luma(_ index: Int) -> Double {
        0.299 * Double(pixels[index])
        + 0.587 * Double(pixels[index + 1])
        + 0.114 * Double(pixels[index + 2])
    }

    var window: [(Double, Int)] = []
    window.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))

    for y in radius..<(height - radius) {
        for x in radius..<(width - radius) {
            let index = (y * width + x) * 4
            // Only touch solid device pixels; the cut edge is not dirt.
            guard pixels[index + 3] > 200 else { continue }

            window.removeAll(keepingCapacity: true)
            for dy in -radius...radius {
                for dx in -radius...radius {
                    let neighbour = ((y + dy) * width + (x + dx)) * 4
                    if pixels[neighbour + 3] > 200 {
                        window.append((luma(neighbour), neighbour))
                    }
                }
            }
            guard window.count >= 9 else { continue }
            window.sort { $0.0 < $1.0 }
            let median = window[window.count / 2]

            if abs(luma(index) - median.0) > cutoff {
                output[index]     = pixels[median.1]
                output[index + 1] = pixels[median.1 + 1]
                output[index + 2] = pixels[median.1 + 2]
                changed += 1
            }
        }
    }

    guard let writeContext = CGContext(data: &output, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: space, bitmapInfo: info),
          let cleaned = writeContext.makeImage() else {
        return (source, 0)
    }
    return (cleaned, changed)
}

/// Even out worn, unevenly-glossed surfaces without touching detail.
///
/// Scuffing on a rubber palm rest is not dirt sitting on the surface, it is the
/// surface -- broad, low-contrast mottling that an outlier filter correctly
/// ignores and that reads, in a product UI, as a filthy app. But those panels
/// carry no information: they are flat black pads. Keys, legends, panel gaps
/// and the device outline do carry information.
///
/// So the split is by local variance, not by position. Where a neighbourhood is
/// featureless the pixel is replaced by that neighbourhood's mean, which erases
/// mottling while preserving large-scale shading. Where it is busy -- any edge,
/// any legend -- the pixel is left exactly as shot. Because the test window is
/// large, edges protect a margin around themselves and nothing smears into them.
///
/// Integral images keep this O(1) per pixel; a naive median over an 11x11
/// window is too slow to iterate on.
func flattenSurfaces(_ source: CGImage, maxVariance: Double, radius: Int) -> (image: CGImage, changed: Int) {
    let width = source.width, height = source.height
    guard maxVariance > 0, width > radius * 2, height > radius * 2 else { return (source, 0) }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let readContext = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else {
        return (source, 0)
    }
    readContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Integral images over opaque pixels only, so the transparent surround
    // cannot drag the mean toward nothing at the device edge.
    let stride = width + 1
    var count = [Double](repeating: 0, count: stride * (height + 1))
    var sumR = count, sumG = count, sumB = count, sumL = count, sumLL = count

    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            let opaque = pixels[index + 3] > 200
            let r = opaque ? Double(pixels[index]) : 0
            let g = opaque ? Double(pixels[index + 1]) : 0
            let b = opaque ? Double(pixels[index + 2]) : 0
            let l = 0.299 * r + 0.587 * g + 0.114 * b
            let here = (y + 1) * stride + (x + 1)
            let up = y * stride + (x + 1), left = (y + 1) * stride + x, upLeft = y * stride + x
            count[here] = (opaque ? 1 : 0) + count[up] + count[left] - count[upLeft]
            sumR[here]  = r + sumR[up] + sumR[left] - sumR[upLeft]
            sumG[here]  = g + sumG[up] + sumG[left] - sumG[upLeft]
            sumB[here]  = b + sumB[up] + sumB[left] - sumB[upLeft]
            sumL[here]  = l + sumL[up] + sumL[left] - sumL[upLeft]
            sumLL[here] = l * l + sumLL[up] + sumLL[left] - sumLL[upLeft]
        }
    }

    func box(_ table: [Double], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
        table[(y1 + 1) * stride + (x1 + 1)] - table[y0 * stride + (x1 + 1)]
        - table[(y1 + 1) * stride + x0] + table[y0 * stride + x0]
    }

    var output = pixels
    var changed = 0
    let windowArea = Double((radius * 2 + 1) * (radius * 2 + 1))

    for y in radius..<(height - radius) {
        for x in radius..<(width - radius) {
            let index = (y * width + x) * 4
            guard pixels[index + 3] > 200 else { continue }
            let x0 = x - radius, x1 = x + radius, y0 = y - radius, y1 = y + radius

            let n = box(count, x0, y0, x1, y1)
            // Require a full window of device pixels: partial windows sit on the
            // cut edge, where flattening would eat the outline.
            guard n >= windowArea - 0.5 else { continue }

            let mean = box(sumL, x0, y0, x1, y1) / n
            let variance = box(sumLL, x0, y0, x1, y1) / n - mean * mean
            guard variance < maxVariance else { continue }

            output[index]     = UInt8(max(0, min(255, box(sumR, x0, y0, x1, y1) / n)))
            output[index + 1] = UInt8(max(0, min(255, box(sumG, x0, y0, x1, y1) / n)))
            output[index + 2] = UInt8(max(0, min(255, box(sumB, x0, y0, x1, y1) / n)))
            changed += 1
        }
    }

    guard let writeContext = CGContext(data: &output, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: space, bitmapInfo: info),
          let flattened = writeContext.makeImage() else {
        return (source, 0)
    }
    return (flattened, changed)
}

let (finalImage, changedPixels) = dustThreshold > 0
    ? despeckle(rendered, threshold: Double(dustThreshold), radius: 2)
    : (rendered, 0)

let (polishedImage, flattenedPixels) = flattenSurfaces(finalImage,
                                                      maxVariance: flattenVariance,
                                                      radius: 5)

let data = NSMutableData()
guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
    fail("PNG destination failed")
}
CGImageDestinationAddImage(destination, polishedImage, nil)
guard CGImageDestinationFinalize(destination) else { fail("PNG finalize failed") }
let png = data as Data

do {
    try png.write(to: outputURL)
} catch {
    fail("could not write \(outputURL.path): \(error.localizedDescription)")
}


let totalPixels = polishedImage.width * polishedImage.height
let percent = totalPixels > 0 ? Double(changedPixels) * 100.0 / Double(totalPixels) : 0
let flatPercent = totalPixels > 0 ? Double(flattenedPixels) * 100.0 / Double(totalPixels) : 0
print(String(format: "OK  %@  %dx%d  despeckled %d (%.2f%%)  flattened %d (%.1f%%)  %.0f KB",
             outputURL.lastPathComponent,
             polishedImage.width, polishedImage.height,
             changedPixels, percent,
             flattenedPixels, flatPercent,
             Double(png.count) / 1024.0))
