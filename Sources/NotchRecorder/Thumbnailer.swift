import AVFoundation
import Common
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Eight small frames per recording for the gallery card and hover scrub.
enum Thumbnailer {
    static let count = 8

    /// Writes `0.jpg` ... `7.jpg` into `folder`; returns how many were made.
    static func make(video: URL, folder: URL) async -> Int {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: video)
        guard let duration = try? await asset.load(.duration).seconds, duration > 0 else { return 0 }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        var made = 0
        for i in 0..<count {
            let t = duration * (0.04 + 0.92 * Double(i) / Double(count - 1))
            guard let (image, _) = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) else { continue }
            let url = folder.appendingPathComponent("\(i).jpg")
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
            if CGImageDestinationFinalize(dest) { made += 1 }
        }
        return made
    }
}
