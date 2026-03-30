import Foundation
import AppKit
import OnnxRuntimeBindings

class OCREngine: @unchecked Sendable {
    private let encoderSession: ORTSession
    private let decoderSession: ORTSession
    private let tokenizer: Tokenizer
    private let env: ORTEnv

    // FormulaNet config
    private let imageSize = 384
    private let maxTokens = 512
    private let decoderStartTokenId: Int64 = 0
    private let eosTokenId: Int64 = 2
    private let vocabSize = 687
    private let imageMean: Float = 0.7931
    private let imageStd: Float = 0.1738

    init() throws {
        env = try ORTEnv(loggingLevel: .warning)

        let bundle = Bundle.main
        guard let encoderPath = bundle.path(forResource: "encoder_model", ofType: "onnx"),
              let decoderPath = bundle.path(forResource: "decoder_model", ofType: "onnx"),
              let tokenizerPath = bundle.path(forResource: "tokenizer", ofType: "json")
        else {
            throw OCRError.modelNotFound
        }

        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setGraphOptimizationLevel(.all)
        try sessionOptions.setIntraOpNumThreads(4)

        encoderSession = try ORTSession(env: env, modelPath: encoderPath, sessionOptions: sessionOptions)
        decoderSession = try ORTSession(env: env, modelPath: decoderPath, sessionOptions: sessionOptions)
        tokenizer = try Tokenizer(path: tokenizerPath)
    }

    func recognize(image: NSImage) throws -> String {
        let pixelData = try preprocessImage(image)
        let encoderOutput = try runEncoder(pixelData: pixelData)
        let tokenIds = try decode(encoderOutput: encoderOutput)
        return tokenizer.decode(tokenIds: tokenIds)
    }

    // MARK: - Image Preprocessing (FormulaNet pipeline)

    private func preprocessImage(_ image: NSImage) throws -> [Float] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        // 1. Crop white margins
        let cropped = cropMargin(cgImage)

        // 2. Resize maintaining aspect ratio with black padding
        let resized = resizeWithPadding(cropped, targetSize: imageSize)

        // 3. Convert to grayscale and normalize as 3-channel
        return extractGrayscale3Channel(resized)
    }

    /// Matches Python: crop_margin()
    /// Normalizes grayscale range then thresholds at 200
    private func cropMargin(_ image: CGImage) -> CGImage {
        let w = image.width
        let h = image.height
        let colorSpace = CGColorSpaceCreateDeviceGray()

        var grayPixels = [UInt8](repeating: 0, count: w * h)
        guard let context = CGContext(
            data: &grayPixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: colorSpace, bitmapInfo: 0
        ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Normalize to 0-255 range like Python: (data - min) / (max - min) * 255
        var minVal: UInt8 = 255, maxVal: UInt8 = 0
        for p in grayPixels {
            minVal = min(minVal, p)
            maxVal = max(maxVal, p)
        }
        guard maxVal != minVal else { return image }

        // Find bounding box of "text" pixels (normalized value < 200)
        var minX = w, minY = h, maxX = 0, maxY = 0
        let range = Float(maxVal) - Float(minVal)
        for y in 0..<h {
            for x in 0..<w {
                let raw = Float(grayPixels[y * w + x])
                let normalized = (raw - Float(minVal)) / range * 255.0
                if normalized < 200 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard minX <= maxX, minY <= maxY else { return image }

        let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return image.cropping(to: cropRect) ?? image
    }

    /// Matches Python: F.resize(image, min(output_size)) then thumbnail then pad
    /// Step 1: Resize so shorter side = targetSize (may upscale)
    /// Step 2: Thumbnail to fit within targetSize x targetSize (only downscale)
    /// Step 3: Center pad with black to exact targetSize x targetSize
    private func resizeWithPadding(_ image: CGImage, targetSize: Int) -> CGImage {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let target = CGFloat(targetSize)

        // Step 1: F.resize(image, min(output_size)) — resize shorter side to target
        let resizeScale = target / min(srcW, srcH)
        let midW = Int(round(srcW * resizeScale))
        let midH = Int(round(srcH * resizeScale))

        // Step 2: thumbnail — ensure fits within target x target (only shrink)
        let thumbScale = min(1.0, min(target / CGFloat(midW), target / CGFloat(midH)))
        let newW = Int(round(CGFloat(midW) * thumbScale))
        let newH = Int(round(CGFloat(midH) * thumbScale))

        // Resize in RGB
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: targetSize, height: targetSize,
            bitsPerComponent: 8, bytesPerRow: targetSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!

        // Black background (zero-initialized), center the image
        let offsetX = (targetSize - newW) / 2
        let offsetY = (targetSize - newH) / 2
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: offsetX, y: offsetY, width: newW, height: newH))

        return context.makeImage()!
    }

    private func extractGrayscale3Channel(_ image: CGImage) -> [Float] {
        let w = image.width
        let h = image.height

        // Read RGB pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawPixels = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(
            data: &rawPixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Convert to grayscale using OpenCV/BT.601 coefficients (matches Python pipeline)
        // Y = 0.299*R + 0.587*G + 0.114*B
        let pixelCount = w * h
        var result = [Float](repeating: 0, count: 3 * pixelCount)

        for i in 0..<pixelCount {
            let r = Float(rawPixels[i * 4]) / 255.0
            let g = Float(rawPixels[i * 4 + 1]) / 255.0
            let b = Float(rawPixels[i * 4 + 2]) / 255.0
            let gray = 0.299 * r + 0.587 * g + 0.114 * b

            let val = (gray - imageMean) / imageStd
            result[i] = val                      // channel 0
            result[pixelCount + i] = val          // channel 1
            result[2 * pixelCount + i] = val      // channel 2
        }

        return result
    }

    // MARK: - Encoder

    private func runEncoder(pixelData: [Float]) throws -> ORTValue {
        let shape: [NSNumber] = [1, 3, NSNumber(value: imageSize), NSNumber(value: imageSize)]
        let inputData = Data(bytes: pixelData, count: pixelData.count * MemoryLayout<Float>.size)
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: inputData),
            elementType: .float,
            shape: shape
        )

        let outputs = try encoderSession.run(
            withInputs: ["pixel_values": inputTensor],
            outputNames: ["last_hidden_state"],
            runOptions: nil
        )

        guard let output = outputs["last_hidden_state"] else {
            throw OCRError.encoderFailed
        }
        return output
    }

    // MARK: - Decoder (Autoregressive)

    private func decode(encoderOutput: ORTValue) throws -> [Int64] {
        var generatedIds: [Int64] = [decoderStartTokenId]

        for _ in 0..<maxTokens {
            let inputData = Data(bytes: generatedIds, count: generatedIds.count * MemoryLayout<Int64>.size)
            let inputTensor = try ORTValue(
                tensorData: NSMutableData(data: inputData),
                elementType: .int64,
                shape: [1, NSNumber(value: generatedIds.count)]
            )

            let outputs = try decoderSession.run(
                withInputs: [
                    "input_ids": inputTensor,
                    "encoder_hidden_states": encoderOutput,
                ],
                outputNames: ["logits"],
                runOptions: nil
            )

            guard let logitsValue = outputs["logits"] else {
                throw OCRError.decoderFailed
            }

            let logitsData = try logitsValue.tensorData() as Data
            let seqLen = generatedIds.count
            let logitsArray = logitsData.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self))
            }

            let lastOffset = (seqLen - 1) * vocabSize
            var maxVal: Float = -Float.infinity
            var maxIdx: Int64 = 0
            for i in 0..<vocabSize {
                let val = logitsArray[lastOffset + i]
                if val > maxVal {
                    maxVal = val
                    maxIdx = Int64(i)
                }
            }

            if maxIdx == eosTokenId {
                break
            }

            generatedIds.append(maxIdx)
        }

        return Array(generatedIds.dropFirst())
    }
}

enum OCRError: LocalizedError {
    case modelNotFound
    case invalidImage
    case encoderFailed
    case decoderFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Model files not found in app bundle"
        case .invalidImage: return "Could not process the image"
        case .encoderFailed: return "Encoder inference failed"
        case .decoderFailed: return "Decoder inference failed"
        }
    }
}
