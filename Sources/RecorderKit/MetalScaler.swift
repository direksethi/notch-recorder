import CoreVideo
import Foundation
import Metal

public enum ScalerError: Error, LocalizedError {
    case noDevice
    case textureFailed
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDevice: "This Mac has no Metal device."
        case .textureFailed: "Could not wrap a video frame for the GPU."
        case .commandFailed(let m): "GPU scaling failed: \(m)"
        }
    }
}

/// Scales a BGRA frame with Lanczos-3 and writes NV12 (BT.709, video range)
/// straight into an IOSurface-backed pixel buffer, all on the GPU.
public final class MetalScaler {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let horizontal: MTLComputePipelineState
    private let vertical: MTLComputePipelineState
    private let toNV12: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?
    private var intermediates: (h: MTLTexture, v: MTLTexture)?

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw ScalerError.noDevice }
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: Shaders.source, options: nil)
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw ScalerError.commandFailed("missing \(name)") }
            return try device.makeComputePipelineState(function: fn)
        }
        horizontal = try pipeline("scaleHorizontal")
        vertical = try pipeline("scaleVertical")
        toNV12 = try pipeline("rgbToNV12")
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    private struct Params {
        var scale: Float
        var support: Float
        var srcLength: UInt32
    }

    /// `src` is 32BGRA, `dst` is 420YpCbCr8BiPlanarVideoRange with even size.
    public func scale(_ src: CVPixelBuffer, into dst: CVPixelBuffer) throws {
        let sw = CVPixelBufferGetWidth(src), sh = CVPixelBufferGetHeight(src)
        let dw = CVPixelBufferGetWidth(dst), dh = CVPixelBufferGetHeight(dst)
        guard let srcTex = texture(src, plane: 0, format: .bgra8Unorm, width: sw, height: sh),
              let yTex = texture(dst, plane: 0, format: .r8Unorm, width: dw, height: dh),
              let cTex = texture(dst, plane: 1, format: .rg8Unorm, width: dw / 2, height: dh / 2)
        else { throw ScalerError.textureFailed }
        let (hTex, vTex) = try intermediateTextures(srcHeight: sh, width: dw, height: dh)

        guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else {
            throw ScalerError.commandFailed("no command buffer")
        }
        let sx = Float(sw) / Float(dw), sy = Float(sh) / Float(dh)
        var hp = Params(scale: sx, support: 3 * max(sx, 1), srcLength: UInt32(sw))
        var vp = Params(scale: sy, support: 3 * max(sy, 1), srcLength: UInt32(sh))

        enc.setComputePipelineState(horizontal)
        enc.setTexture(srcTex.texture, index: 0)
        enc.setTexture(hTex, index: 1)
        enc.setBytes(&hp, length: MemoryLayout<Params>.stride, index: 0)
        dispatch(enc, horizontal, width: dw, height: sh)

        enc.setComputePipelineState(vertical)
        enc.setTexture(hTex, index: 0)
        enc.setTexture(vTex, index: 1)
        enc.setBytes(&vp, length: MemoryLayout<Params>.stride, index: 0)
        dispatch(enc, vertical, width: dw, height: dh)

        enc.setComputePipelineState(toNV12)
        enc.setTexture(vTex, index: 0)
        enc.setTexture(yTex.texture, index: 1)
        enc.setTexture(cTex.texture, index: 2)
        dispatch(enc, toNV12, width: dw / 2, height: dh / 2)
        enc.endEncoding()

        // Keep the CVMetalTextures alive until the GPU is done with them.
        let keepAlive = [srcTex, yTex, cTex]
        cmd.addCompletedHandler { _ in _ = keepAlive }
        cmd.commit()
        cmd.waitUntilCompleted()
        if let error = cmd.error { throw ScalerError.commandFailed(error.localizedDescription) }
    }

    private struct Wrapped {
        let cv: CVMetalTexture
        let texture: MTLTexture
    }

    private func texture(_ pb: CVPixelBuffer, plane: Int, format: MTLPixelFormat, width: Int, height: Int) -> Wrapped? {
        guard let cache = textureCache else { return nil }
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, format, width, height, plane, &cvTex)
        guard status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return nil }
        return Wrapped(cv: cvTex, texture: tex)
    }

    private func intermediateTextures(srcHeight: Int, width: Int, height: Int) throws -> (MTLTexture, MTLTexture) {
        if let t = intermediates, t.h.width == width, t.h.height == srcHeight, t.v.height == height {
            return (t.h, t.v)
        }
        func make(_ w: Int, _ h: Int) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead, .shaderWrite]
            d.storageMode = .private
            guard let t = device.makeTexture(descriptor: d) else { throw ScalerError.textureFailed }
            return t
        }
        let pair = (h: try make(width, srcHeight), v: try make(width, height))
        intermediates = pair
        return (pair.h, pair.v)
    }

    private func dispatch(_ enc: MTLComputeCommandEncoder, _ p: MTLComputePipelineState, width: Int, height: Int) {
        let tw = p.threadExecutionWidth
        let th = max(1, p.maxTotalThreadsPerThreadgroup / tw)
        enc.dispatchThreads(
            MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: tw, height: th, depth: 1))
    }

    /// Releases cached textures (call when a recording ends).
    public func flush() {
        intermediates = nil
        if let cache = textureCache { CVMetalTextureCacheFlush(cache, 0) }
    }
}

public enum PixelBuffers {
    /// IOSurface-backed, Metal-compatible pixel buffer attributes.
    public static func attributes(width: Int, height: Int, format: OSType) -> [CFString: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey: format,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
    }

    public static func make(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, format, attributes(width: width, height: height, format: format) as CFDictionary, &pb)
        return pb
    }

    /// Tags a buffer as BT.709 so the encoder and players read colour right.
    public static func tagRec709(_ pb: CVPixelBuffer) {
        CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}
