import Flutter
import UIKit
import CoreImage

/// Platform plugin for real-time era-style filters using Core Image.
///
/// CIFilter-based: no ML model needed, runs at 60fps on any modern iPhone.
/// Each era applies a chain of CIFilters to approximate the photographic
/// look of that historical period.
class StyleTransferPlugin: NSObject, FlutterPlugin {

    private let ciContext: CIContext
    private var currentEraId: Int = 0

    override init() {
        // Use Metal-backed context for GPU acceleration
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false,
        ])
        super.init()
    }

    // Convenience init for plugin registration
    init(registrar: FlutterPluginRegistrar) {
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: false,
        ])
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
            // No model to load — CIFilters are built-in
            result(true)
        case "setStyle":
            if let args = call.arguments as? [String: Any],
               let eraId = args["eraId"] as? Int {
                currentEraId = eraId
            }
            result(true)
        case "transferFrame":
            guard let args = call.arguments as? [String: Any],
                  let jpegData = (args["jpeg"] as? FlutterStandardTypedData)?.data else {
                result(FlutterError(code: "INVALID_ARGS", message: "jpeg required", details: nil))
                return
            }
            let quality = args["quality"] as? Int ?? 75
            let eraId = args["eraId"] as? Int ?? currentEraId
            applyFilter(jpegData: jpegData, eraId: eraId, quality: quality, result: result)
        case "isReady":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Filter Application

    private func applyFilter(jpegData: Data, eraId: Int, quality: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            guard let inputImage = CIImage(data: jpegData) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DECODE_ERROR", message: "Failed to decode JPEG", details: nil))
                }
                return
            }

            let filtered = self.filterForEra(eraId, image: inputImage)

            guard let cgImage = self.ciContext.createCGImage(filtered, from: filtered.extent) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "RENDER_ERROR", message: "Failed to render", details: nil))
                }
                return
            }

            let uiImage = UIImage(cgImage: cgImage)
            guard let outputData = uiImage.jpegData(compressionQuality: CGFloat(quality) / 100.0) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "ENCODE_ERROR", message: "Failed to encode JPEG", details: nil))
                }
                return
            }

            DispatchQueue.main.async {
                result(FlutterStandardTypedData(bytes: outputData))
            }
        }
    }

    // MARK: - Era Filters

    private func filterForEra(_ eraId: Int, image: CIImage) -> CIImage {
        switch eraId {
        case 0x01: return taishoFilter(image)
        case 0x02: return showaEarlyFilter(image)
        case 0x03: return showaMidFilter(image)
        case 0x04: return meijiFilter(image)
        default:   return image  // passthrough
        }
    }

    /// 大正時代 (1912-1926): Warm sepia, hand-colored photo look
    private func taishoFilter(_ image: CIImage) -> CIImage {
        var result = image

        // Sepia tone
        if let sepia = CIFilter(name: "CISepiaTone") {
            sepia.setValue(result, forKey: kCIInputImageKey)
            sepia.setValue(0.7, forKey: kCIInputIntensityKey)
            result = sepia.outputImage ?? result
        }

        // Slight warmth via color controls
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(result, forKey: kCIInputImageKey)
            color.setValue(0.95, forKey: kCIInputSaturationKey)
            color.setValue(0.02, forKey: kCIInputBrightnessKey)
            color.setValue(1.05, forKey: kCIInputContrastKey)
            result = color.outputImage ?? result
        }

        // Soft vignette
        result = applyVignette(result, intensity: 1.2, radius: 1.5)

        // Slight blur for soft focus
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(result, forKey: kCIInputImageKey)
            blur.setValue(0.8, forKey: kCIInputRadiusKey)
            result = blur.outputImage?.cropped(to: image.extent) ?? result
        }

        // Film grain noise
        result = applyGrain(result, amount: 0.04)

        return result
    }

    /// 昭和初期 (1926-1945): High contrast black and white
    private func showaEarlyFilter(_ image: CIImage) -> CIImage {
        var result = image

        // Convert to B&W with high contrast (Noir)
        if let noir = CIFilter(name: "CIPhotoEffectNoir") {
            noir.setValue(result, forKey: kCIInputImageKey)
            result = noir.outputImage ?? result
        }

        // Boost contrast
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(result, forKey: kCIInputImageKey)
            color.setValue(0.0, forKey: kCIInputSaturationKey)
            color.setValue(-0.02, forKey: kCIInputBrightnessKey)
            color.setValue(1.3, forKey: kCIInputContrastKey)
            result = color.outputImage ?? result
        }

        // Vignette
        result = applyVignette(result, intensity: 1.0, radius: 1.8)

        // Heavier grain
        result = applyGrain(result, amount: 0.06)

        return result
    }

    /// 昭和中期 (1945-1970): Faded Kodachrome color film
    private func showaMidFilter(_ image: CIImage) -> CIImage {
        var result = image

        // Faded film look
        if let fade = CIFilter(name: "CIPhotoEffectProcess") {
            fade.setValue(result, forKey: kCIInputImageKey)
            result = fade.outputImage ?? result
        }

        // Reduce saturation + warm shift
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(result, forKey: kCIInputImageKey)
            color.setValue(0.75, forKey: kCIInputSaturationKey)
            color.setValue(0.03, forKey: kCIInputBrightnessKey)
            color.setValue(0.95, forKey: kCIInputContrastKey)
            result = color.outputImage ?? result
        }

        // Warm temperature shift
        if let temp = CIFilter(name: "CITemperatureAndTint") {
            temp.setValue(result, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6800, y: 0), forKey: "inputNeutral")  // warm
            temp.setValue(CIVector(x: 6200, y: 0), forKey: "inputTargetNeutral")
            result = temp.outputImage ?? result
        }

        // Light vignette
        result = applyVignette(result, intensity: 0.6, radius: 2.0)

        // Light grain
        result = applyGrain(result, amount: 0.03)

        return result
    }

    /// 明治時代 (1868-1912): Dark sepia, strong vignette, early photography
    private func meijiFilter(_ image: CIImage) -> CIImage {
        var result = image

        // Strong sepia
        if let sepia = CIFilter(name: "CISepiaTone") {
            sepia.setValue(result, forKey: kCIInputImageKey)
            sepia.setValue(0.9, forKey: kCIInputIntensityKey)
            result = sepia.outputImage ?? result
        }

        // Low contrast, slightly dark
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(result, forKey: kCIInputImageKey)
            color.setValue(0.3, forKey: kCIInputSaturationKey)
            color.setValue(-0.05, forKey: kCIInputBrightnessKey)
            color.setValue(0.85, forKey: kCIInputContrastKey)
            result = color.outputImage ?? result
        }

        // Heavy vignette
        result = applyVignette(result, intensity: 2.0, radius: 1.0)

        // Soft blur (early lenses)
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(result, forKey: kCIInputImageKey)
            blur.setValue(1.5, forKey: kCIInputRadiusKey)
            result = blur.outputImage?.cropped(to: image.extent) ?? result
        }

        // Heavy grain
        result = applyGrain(result, amount: 0.08)

        return result
    }

    // MARK: - Shared Filter Effects

    private func applyVignette(_ image: CIImage, intensity: Double, radius: Double) -> CIImage {
        guard let vignette = CIFilter(name: "CIVignette") else { return image }
        vignette.setValue(image, forKey: kCIInputImageKey)
        vignette.setValue(intensity, forKey: kCIInputIntensityKey)
        vignette.setValue(radius, forKey: kCIInputRadiusKey)
        return vignette.outputImage ?? image
    }

    private func applyGrain(_ image: CIImage, amount: Double) -> CIImage {
        // Generate noise
        guard let noise = CIFilter(name: "CIRandomGenerator") else { return image }
        guard let noiseImage = noise.outputImage else { return image }

        // Scale and desaturate noise
        let cropped = noiseImage.cropped(to: image.extent)

        guard let colorControls = CIFilter(name: "CIColorControls") else { return image }
        colorControls.setValue(cropped, forKey: kCIInputImageKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
        colorControls.setValue(-0.5, forKey: kCIInputBrightnessKey)
        guard let grayNoise = colorControls.outputImage else { return image }

        // Blend noise with original
        guard let blend = CIFilter(name: "CISourceOverCompositing") else { return image }
        let adjustedNoise = grayNoise.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        ])
        blend.setValue(adjustedNoise, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage ?? image
    }
}
