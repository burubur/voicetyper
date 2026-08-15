import Foundation
import SherpaOnnx
import SherpaOnnxC

// MARK: - ParakeetTranscriber

/// Adapter that uses sherpa-onnx to run NVIDIA Parakeet models (CTC and Transducer).
final class ParakeetTranscriber: Transcriber, @unchecked Sendable {
    private let recognizer: SherpaOnnxOfflineRecognizer
    private(set) var activeVocabulary: [String] = []

    /// Initializes the transcriber by loading an ONNX Parakeet model directory.
    /// - Parameter modelDir: Path to the directory containing the ONNX files and tokens.txt.
    init(modelDir: URL, vocabulary: [String] = []) throws {
        self.activeVocabulary = vocabulary
        let encoderPath = modelDir.appendingPathComponent("encoder.int8.onnx").path
        let decoderPath = modelDir.appendingPathComponent("decoder.int8.onnx").path
        let joinerPath = modelDir.appendingPathComponent("joiner.int8.onnx").path
        let tokensPath = modelDir.appendingPathComponent("tokens.txt").path
        let modelPath = modelDir.appendingPathComponent("model.int8.onnx").path

        var allocatedPointers: [UnsafeMutablePointer<CChar>] = []
        func cString(_ str: String) -> UnsafePointer<CChar> {
            let ptr = strdup(str)!
            allocatedPointers.append(ptr)
            return UnsafePointer(ptr)
        }
        defer {
            for ptr in allocatedPointers {
                free(ptr)
            }
        }

        let fileManager = FileManager.default
        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80
        )
        var config = SherpaOnnxOfflineRecognizerConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineRecognizerConfig>.size)
        config.feat_config = featConfig
        config.decoding_method = cString("greedy_search")
        config.max_active_paths = 4

        var modelConfig = SherpaOnnxOfflineModelConfig()
        memset(&modelConfig, 0, MemoryLayout<SherpaOnnxOfflineModelConfig>.size)
        modelConfig.tokens = cString(tokensPath)
        modelConfig.num_threads = 4
        modelConfig.debug = 0
        modelConfig.provider = cString("cpu")
        
        if fileManager.fileExists(atPath: joinerPath) {
            // Transducer model (parakeet-unified)
            var transducerConfig = SherpaOnnxOfflineTransducerModelConfig()
            memset(&transducerConfig, 0, MemoryLayout<SherpaOnnxOfflineTransducerModelConfig>.size)
            transducerConfig.encoder = cString(encoderPath)
            transducerConfig.decoder = cString(decoderPath)
            transducerConfig.joiner = cString(joinerPath)
            
            modelConfig.transducer = transducerConfig
            modelConfig.model_type = cString("nemo_transducer")
        } else if fileManager.fileExists(atPath: modelPath) {
            // CTC model (parakeet-tdt)
            var ctcConfig = SherpaOnnxOfflineNemoEncDecCtcModelConfig()
            memset(&ctcConfig, 0, MemoryLayout<SherpaOnnxOfflineNemoEncDecCtcModelConfig>.size)
            ctcConfig.model = cString(modelPath)
            
            modelConfig.nemo_ctc = ctcConfig
            modelConfig.model_type = cString("nemo_ctc")
        } else {
            throw NSError(domain: "ParakeetTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Parakeet model directory structure"])
        }

        config.model_config = modelConfig
        
        self.recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    }

    /// Sets or updates the active vocabulary terms for canonical normalization.
    func setVocabulary(terms: [String]) {
        self.activeVocabulary = terms
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
            
            // Post-processing canonical vocabulary terms
            return VocabularySanitizer.sanitizeOutput(
                transcription: text,
                injectedPrompt: nil,
                activeVocabulary: self.activeVocabulary
            )
        }.value
    }
}
