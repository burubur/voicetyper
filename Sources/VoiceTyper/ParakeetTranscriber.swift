import Foundation
import SherpaOnnx
import SherpaOnnxC

// MARK: - ParakeetTranscriber

/// Adapter that uses sherpa-onnx to run NVIDIA Parakeet models (CTC and Transducer).
final class ParakeetTranscriber: Transcriber, @unchecked Sendable {
    private let recognizer: SherpaOnnxOfflineRecognizer

    /// Initializes the transcriber by loading an ONNX Parakeet model directory.
    /// - Parameter modelDir: Path to the directory containing the ONNX files and tokens.txt.
    init(modelDir: URL) throws {
        let encoderPath = modelDir.appendingPathComponent("encoder.int8.onnx").path
        let decoderPath = modelDir.appendingPathComponent("decoder.int8.onnx").path
        let joinerPath = modelDir.appendingPathComponent("joiner.int8.onnx").path
        let tokensPath = modelDir.appendingPathComponent("tokens.txt").path
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx").path

        let fileManager = FileManager.default
        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80
        )
        var config: SherpaOnnxOfflineRecognizerConfig
        
        if fileManager.fileExists(atPath: joinerPath) {
            // Transducer model (parakeet-unified)
            let transducerConfig = sherpaOnnxOfflineTransducerModelConfig(
                encoder: encoderPath,
                decoder: decoderPath,
                joiner: joinerPath
            )
            let modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokensPath,
                transducer: transducerConfig,
                numThreads: 4,
                debug: 0,
                modelType: "nemo_transducer"
            )
            config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig
            )
        } else if fileManager.fileExists(atPath: modelPath) {
            // CTC model (parakeet-tdt)
            let ctcConfig = sherpaOnnxOfflineNemoEncDecCtcModelConfig(
                model: modelPath
            )
            let modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: tokensPath,
                nemoCtc: ctcConfig,
                numThreads: 4,
                debug: 0,
                modelType: "nemo_ctc"
            )
            config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig
            )
        } else {
            throw NSError(domain: "ParakeetTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Parakeet model directory structure"])
        }
        
        self.recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    /// Transcribes 16kHz mono PCM float audio frames into text.
    func transcribe(audioFrames: [Float]) async throws -> String {
        return await Task.detached {
            let result = self.recognizer.decode(samples: audioFrames, sampleRate: 16000)
            
            // Clean up output string
            var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Post-processing to enforce standard spacing
            text = text.replacingOccurrences(of: " ,", with: ",")
            text = text.replacingOccurrences(of: " .", with: ".")
            text = text.replacingOccurrences(of: " ?", with: "?")
            text = text.replacingOccurrences(of: " !", with: "!")
            
            // Capitalize first letter
            if let firstChar = text.first {
                text = String(firstChar).uppercased() + text.dropFirst()
            }
            
            return text
        }.value
    }
}
