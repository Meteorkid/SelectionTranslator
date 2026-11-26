import CoreGraphics
import CoreImage

/// Produces contrast/sharpness variants for a second OCR attempt.
///
/// The original image is always tried first. This helper is only used when
/// Vision returns no text, very little text, or a low-confidence result.
enum OCRImageEnhancer {
    static func enhanced(from image: CGImage, inverted: Bool = false) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }

        let longestSide = max(width, height)
        let scale: CGFloat
        if longestSide < 1_600 {
            scale = 2
        } else if longestSide < 2_400 {
            scale = 1.5
        } else {
            scale = 1
        }

        var output = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 0,
                    kCIInputContrastKey: 1.45,
                    kCIInputBrightnessKey: 0.02
                ]
            )
            .applyingFilter(
                "CISharpenLuminance",
                parameters: [kCIInputSharpnessKey: 0.65]
            )

        if inverted {
            output = output.applyingFilter("CIColorInvert")
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(output, from: output.extent.integral)
    }
}
