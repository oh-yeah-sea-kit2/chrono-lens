import Flutter
import UIKit
import CoreML
import CoreImage
import AVFoundation

/// Platform plugin for real-time neural style transfer using CoreML.
///
/// For initial implementation, we accept JPEG bytes from Dart, run CoreML inference,
/// and return stylized JPEG bytes. This avoids the complexity of FlutterTexture
/// and native camera management while still being fast enough for the preview.
///
/// Future optimization: FlutterTexture + native AVCaptureSession for zero-copy.
class StyleTransferPlugin: NSObject, FlutterPlugin {

    private let registrar: FlutterPluginRegistrar
    private var styleModel: MLModel?
    private var cachedStyleImage: CGImage?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Track loading state
    private var isModelLoaded = false

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.chrono_lens/style_transfer",
            binaryMessenger: registrar.messenger()
        )
        let instance = StyleTransferPlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            loadModel(result: result)
        case "setStyle":
            guard let args = call.arguments as? [String: Any],
                  let jpegData = (args["jpeg"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "INVALID_ARGS", message: "jpeg required", details: nil))
                return
            }
            setStyle(jpegData: jpegData, result: result)
        case "transferFrame":
            guard let args = call.arguments as? [String: Any],
                  let jpegData = (args["jpeg"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "INVALID_ARGS", message: "jpeg required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 75
            transferFrame(jpegData: jpegData, quality: quality, result: result)
        case "isReady":
            result(isModelLoaded && cachedStyleImage != nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Model Loading

    private func loadModel(result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Look for the compiled model in the app bundle
            // The .mlpackage gets compiled to .mlmodelc by Xcode automatically
            // Xcode compiles .mlpackage → .mlmodelc in the app bundle.
            // Also try .mlpackage directly as fallback (runtime compilation).
            let modelURL: URL? = Bundle.main.url(forResource: "StyleTransfer", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "StyleTransfer", withExtension: "mlpackage")

            guard let url = modelURL else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "MODEL_NOT_FOUND",
                                      message: "StyleTransfer model not found in bundle",
                                      details: nil))
                }
                return
            }

            let finalURL: URL
            if url.pathExtension == "mlpackage" {
                do {
                    finalURL = try MLModel.compileModel(at: url)
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "COMPILE_ERROR", message: error.localizedDescription, details: nil))
                    }
                    return
                }
            } else {
                finalURL = url
            }

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                self.styleModel = try MLModel(contentsOf: finalURL, configuration: config)
                self.isModelLoaded = true
                DispatchQueue.main.async { result(true) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "MODEL_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // MARK: - Style Setting

    private func setStyle(jpegData: Data, result: @escaping FlutterResult) {
        guard let uiImage = UIImage(data: jpegData),
              let cgImage = uiImage.cgImage else {
            result(FlutterError(code: "DECODE_ERROR", message: "Failed to decode style JPEG", details: nil))
            return
        }
        cachedStyleImage = cgImage
        result(true)
    }

    // MARK: - Frame Transfer

    private func transferFrame(jpegData: Data, quality: Int, result: @escaping FlutterResult) {
        guard let model = styleModel else {
            result(FlutterError(code: "NOT_READY", message: "Model not loaded", details: nil))
            return
        }
        guard let styleImage = cachedStyleImage else {
            // No style set — return input as-is (passthrough)
            result(FlutterStandardTypedData(bytes: jpegData))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let contentUIImage = UIImage(data: jpegData),
                  let contentCGImage = contentUIImage.cgImage else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_ERROR", message: "Failed to decode content JPEG", details: nil))
                }
                return
            }

            do {
                let stylized = try self.runInference(
                    model: model,
                    contentImage: contentCGImage,
                    styleImage: styleImage
                )
                let outputData = self.cgImageToJpeg(stylized, quality: quality)
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: outputData))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFERENCE_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // MARK: - CoreML Inference

    private func runInference(model: MLModel, contentImage: CGImage, styleImage: CGImage) throws -> CGImage {
        let contentSize = 384
        let styleSize = 256

        // Resize images to model input sizes
        let contentResized = resizeCGImage(contentImage, to: CGSize(width: contentSize, height: contentSize))
        let styleResized = resizeCGImage(styleImage, to: CGSize(width: styleSize, height: styleSize))

        // Create MLMultiArray or CVPixelBuffer inputs depending on model
        let contentBuffer = try cgImageToPixelBuffer(contentResized, size: contentSize)
        let styleBuffer = try cgImageToPixelBuffer(styleResized, size: styleSize)

        // Build feature provider
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "content_image": MLFeatureValue(pixelBuffer: contentBuffer),
            "style_image": MLFeatureValue(pixelBuffer: styleBuffer),
        ])

        let output = try model.prediction(from: input)

        // Try to extract output as pixel buffer (image) or multiarray (tensor)
        for name in ["stylized_image", "Identity"] + Array(output.featureNames) {
            if let fv = output.featureValue(for: name) {
                // Case 1: output is an image (CVPixelBuffer)
                if let pb = fv.imageBufferValue {
                    return pixelBufferToCGImage(pb)
                }
                // Case 2: output is a MultiArray (float tensor)
                if let ma = fv.multiArrayValue {
                    return multiArrayToCGImage(ma, width: contentSize, height: contentSize)
                }
            }
        }

        throw NSError(domain: "StyleTransfer", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "No image output found in model prediction"
        ])
    }

    // MARK: - Image Utilities

    private func resizeCGImage(_ image: CGImage, to size: CGSize) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }

    private func cgImageToPixelBuffer(_ image: CGImage, size: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            size, size,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "CVPixelBuffer", code: Int(status))
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        return buffer
    }

    private func pixelBufferToCGImage(_ pixelBuffer: CVPixelBuffer) -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)!
    }

    /// Convert MLMultiArray [1, H, W, 3] float (0-1 range) to CGImage
    private func multiArrayToCGImage(_ array: MLMultiArray, width: Int, height: Int) -> CGImage {
        let count = width * height
        var pixels = [UInt8](repeating: 0, count: count * 4) // RGBA

        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)

        for i in 0..<count {
            let r = UInt8(min(max(ptr[i * 3 + 0], 0), 1) * 255)
            let g = UInt8(min(max(ptr[i * 3 + 1], 0), 1) * 255)
            let b = UInt8(min(max(ptr[i * 3 + 2], 0), 1) * 255)
            pixels[i * 4 + 0] = r
            pixels[i * 4 + 1] = g
            pixels[i * 4 + 2] = b
            pixels[i * 4 + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        return context.makeImage()!
    }

    private func cgImageToJpeg(_ image: CGImage, quality: Int) -> Data {
        let uiImage = UIImage(cgImage: image)
        return uiImage.jpegData(compressionQuality: CGFloat(quality) / 100.0)!
    }
}
