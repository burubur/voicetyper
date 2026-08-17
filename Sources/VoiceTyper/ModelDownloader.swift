import Foundation

@MainActor
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()
    
    var isDownloading = false
    var isExtracting = false
    var progress: Double = 0.0
    var statusText: String = "Preparing download..."
    
    var progressCallback: ((Double, String) -> Void)?
    
    private var downloadTask: URLSessionDownloadTask?
    private var completionCallback: ((Bool) -> Void)?
    
    private let modelName = "ggml-base.en.bin"
    private let downloadURL: URL = {
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin") else {
            fatalError("Invalid static model download URL configuration")
        }
        return url
    }()
    
    private var modelDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".voicetyper")
    }
    
    var isModelInstalled: Bool {
        let targetDir = modelDir.appendingPathComponent(modelName)
        return FileManager.default.fileExists(atPath: targetDir.path)
    }
    
    func checkAndDownloadModel(completion: @escaping (Bool) -> Void) {
        if isModelInstalled {
            completion(true)
            return
        }
        
        self.completionCallback = completion
        
        do {
            if !FileManager.default.fileExists(atPath: modelDir.path) {
                try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
            }
        } catch {
            print("Failed to create model directory: \(error)")
            completion(false)
            return
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        isDownloading = true
        progress = 0.0
        statusText = "Downloading Voice Model..."
        
        downloadTask = session.downloadTask(with: downloadURL)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusText = "Download Cancelled"
        completionCallback?(false)
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let percentage = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.progress = percentage
                let mbWritten = totalBytesWritten / 1_048_576
                let mbTotal = totalBytesExpectedToWrite / 1_048_576
                self.statusText = "Downloading... \(mbWritten)MB / \(mbTotal)MB"
                self.progressCallback?(self.progress, self.statusText)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isDownloading = false
            session.finishTasksAndInvalidate()
            
            let targetFile = self.modelDir.appendingPathComponent(self.modelName)
            do {
                if FileManager.default.fileExists(atPath: targetFile.path) {
                    _ = try FileManager.default.replaceItemAt(targetFile, withItemAt: location, backupItemName: nil, options: .usingNewMetadataOnly)
                } else {
                    try FileManager.default.moveItem(at: location, to: targetFile)
                }
                self.statusText = "Ready!"
                self.completionCallback?(true)
            } catch {
                print("File installation failed: \(error)")
                self.statusText = "Failed to save model"
                self.completionCallback?(false)
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("Download failed: \(error.localizedDescription)")
                self.isDownloading = false
                self.statusText = "Download Failed"
                self.completionCallback?(false)
                session.finishTasksAndInvalidate()
            }
        }
    }
}
