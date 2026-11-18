import Common
import CoreMedia
import Foundation
import VideoToolbox

public enum EncoderError: Error, LocalizedError {
    case sessionFailed(OSStatus)
    case propertyFailed(String, OSStatus)
    case encodeFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .sessionFailed(let s): "Could not start the hardware HEVC encoder (\(s))."
        case .propertyFailed(let k, let s): "The encoder rejected \(k) (\(s))."
        case .encodeFailed(let s): "A frame failed to encode (\(s))."
        }
    }
}

/// Apple's hardware HEVC encoder configured exactly as OBS 32 configures it
/// for "Apple VT HEVC Hardware Encoder", rate control CRF, quality 60
/// (obs-studio plugins/mac-videotoolbox/encoder.c).
public final class VideoEncoder {
    public static let encoderID = "com.apple.videotoolbox.videoencoder.ave.hevc"

    public let session: VTCompressionSession
    public let width: Int
    public let height: Int
    /// Called on VideoToolbox's thread with each compressed frame, in decode order.
    public var onEncoded: ((CMSampleBuffer) -> Void)?
    public var onError: ((Error) -> Void)?

    public init(width: Int, height: Int, settings: RecordingSettings) throws {
        self.width = width
        self.height = height
        let spec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EncoderID: Self.encoderID,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
        ]
        let source = PixelBuffers.attributes(width: width, height: height, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        var made: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary, imageBufferAttributes: source as CFDictionary,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made)
        guard status == noErr, let made else { throw EncoderError.sessionFailed(status) }
        session = made

        func set(_ key: CFString, _ value: CFTypeRef, _ name: String) throws {
            let s = VTSessionSetProperty(session, key: key, value: value)
            guard s == noErr else { throw EncoderError.propertyFailed(name, s) }
        }
        try set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, settings.keyframeSeconds as CFNumber, "MaxKeyFrameIntervalDuration")
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, settings.keyframeInterval as CFNumber, "MaxKeyFrameInterval")
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, Int(settings.fps) as CFNumber, "ExpectedFrameRate")
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue, "AllowFrameReordering")
        try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel, "ProfileLevel")
        try set(kVTCompressionPropertyKey_Quality, Float(settings.quality) as CFNumber, "Quality")
        // OBS turns spatial adaptive quantisation on (default level) in CRF
        // mode on macOS 15+. Not every encoder build supports it; skip if not.
        let aq = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_SpatialAdaptiveQPLevel, value: kVTQPModulationLevel_Default as CFNumber)
        if aq != noErr { Log.recorder.info("SpatialAdaptiveQPLevel unsupported (\(aq))") }
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse, "RealTime")
        try set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2, "ColorPrimaries")
        try set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2, "TransferFunction")
        try set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2, "YCbCrMatrix")
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        VTCompressionSessionInvalidate(session)
    }

    /// Buffers from this pool are already in the encoder's preferred layout.
    public var pixelBufferPool: CVPixelBufferPool? {
        VTCompressionSessionGetPixelBufferPool(session)
    }

    public func makeBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        }
        let buffer = pb ?? PixelBuffers.make(width: width, height: height, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        if let buffer { PixelBuffers.tagRec709(buffer) }
        return buffer
    }

    public func encode(_ pb: CVPixelBuffer, pts: CMTime, duration: CMTime) {
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pb, presentationTimeStamp: pts, duration: duration,
            frameProperties: nil, infoFlagsOut: nil
        ) { [weak self] status, _, sample in
            guard let self else { return }
            if status != noErr {
                self.onError?(EncoderError.encodeFailed(status))
            } else if let sample {
                self.onEncoded?(sample)
            }
        }
        if status != noErr { onError?(EncoderError.encodeFailed(status)) }
    }

    /// Emits every pending frame (B-frames are held back until this).
    public func flush() {
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    public func property(_ key: CFString) -> Any? {
        var value: CFTypeRef?
        VTSessionCopyProperty(session, key: key, allocator: nil, valueOut: &value)
        return value
    }
}
